import Foundation
import CoreAudio
import AppKit
import os

final class AudioMeterService: ObservableObject, @unchecked Sendable {
    static let shared = AudioMeterService()

    static let barCount = 10

    @Published private(set) var bars: [Float] = Array(repeating: 0, count: barCount)
    @Published private(set) var level: Float = 0
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var activeSources: [SourceApp] = []
    @Published private(set) var runningOutputDeviceIDs: Set<String> = []

    struct SourceApp: Equatable, Identifiable {
        let id: String
        let name: String
        let icon: NSImage?

        static func == (lhs: SourceApp, rhs: SourceApp) -> Bool {
            lhs.id == rhs.id && lhs.name == rhs.name
        }
    }

    private var tapID: AudioObjectID = 0
    private var aggregateID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var currentOutputUID: String?

    private var lock = os_unfair_lock_s()
    private var atomicRMS: Float = 0
    private var atomicPeak: Float = 0
    private var ioProcCallCount: Int = 0

    private var refreshTimer: Timer?
    private var sourceTimer: Timer?
    private var defaultDeviceListenerInstalled = false
    private var processListListenerInstalled = false
    private var rebuildWorkItem: DispatchWorkItem?

    private var ringBuffer: [Float] = Array(repeating: 0, count: barCount)
    private var ringHead: Int = 0
    private var displayBuffer: [Float] = Array(repeating: 0, count: barCount)
    private var silentTickCount: Int = 0
    private static let silentPauseThreshold: Int = 20

    private init() {
        if #available(macOS 14.2, *) {
            setupTap()
            observeDefaultDeviceChanges()
            observeProcessListChanges()
            scheduleSourcePolling()
        }
        scheduleRefresh()
        refreshRunningOutputs()
    }

    private func refreshRunningOutputs() {
        let outputs = AudioService.outputDevices()
        var running: Set<String> = []
        for device in outputs {
            if AudioService.isRunning(deviceID: device.id) {
                running.insert(device.id)
            }
        }
        if running != runningOutputDeviceIDs {
            if Thread.isMainThread {
                runningOutputDeviceIDs = running
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if running != self.runningOutputDeviceIDs {
                        self.runningOutputDeviceIDs = running
                    }
                }
            }
        }
    }

    @available(macOS 14.2, *)
    private func setupTap() {
        teardown()
        guard let outputUID = defaultOutputUID() else {
            report("no default output device")
            return
        }
        currentOutputUID = outputUID

        let processes = audioProcessObjectIDs()
        DebugLog.write("AudioMeter.audioProcesses count=\(processes.count) ids=\(processes)")
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.isPrivate = false
        desc.isExclusive = false
        desc.muteBehavior = .unmuted
        desc.name = "SiftVisualizerTap"

        var tap: AudioObjectID = 0
        let tapErr = AudioHardwareCreateProcessTap(desc, &tap)
        DebugLog.write("AudioMeter.createTap err=\(tapErr) id=\(tap)")
        guard tapErr == noErr, tap != 0 else {
            report("tap create failed: OSStatus \(tapErr) (likely missing system-audio recording permission — check System Settings → Privacy & Security → Microphone or System Audio Recording, and grant Sift access)")
            return
        }
        tapID = tap

        guard let tapUID = readCFStringProperty(tap, kAudioTapPropertyUID) else {
            report("tap UID read failed")
            teardown()
            return
        }
        DebugLog.write("AudioMeter.tapUID=\(tapUID)")

        let aggregateUID = "io.sift.visualizer.\(ProcessInfo.processInfo.processIdentifier).\(UInt64.random(in: 0..<UInt64.max))"
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sift Aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUID,
                    kAudioSubTapDriftCompensationKey: 1
                ] as [String: Any]
            ]
        ]
        var agg: AudioDeviceID = 0
        let aggErr = AudioHardwareCreateAggregateDevice(aggregateDict as CFDictionary, &agg)
        DebugLog.write("AudioMeter.createAggregate err=\(aggErr) id=\(agg) outputUID=\(outputUID)")
        guard aggErr == noErr, agg != 0 else {
            report("aggregate create failed: OSStatus \(aggErr)")
            teardown()
            return
        }
        aggregateID = agg

        var procID: AudioDeviceIOProcID?
        let installErr = AudioDeviceCreateIOProcIDWithBlock(&procID, agg, nil) { [weak self] _, inputData, _, _, _ in
            self?.process(inputData)
        }
        DebugLog.write("AudioMeter.installIOProc err=\(installErr)")
        guard installErr == noErr, let procID else {
            report("IOProc install failed: OSStatus \(installErr)")
            teardown()
            return
        }
        ioProcID = procID
        logStreamFormats(agg)
        let startErr = AudioDeviceStart(agg, procID)
        DebugLog.write("AudioMeter.start err=\(startErr)")
        guard startErr == noErr else {
            report("AudioDeviceStart failed: OSStatus \(startErr)")
            teardown()
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.isAvailable = true
            self?.lastError = nil
        }
    }

    private func logStreamFormats(_ device: AudioDeviceID) {
        for scope in [(kAudioObjectPropertyScopeInput, "input"), (kAudioObjectPropertyScopeOutput, "output")] {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: scope.0,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamsSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(device, &streamAddr, 0, nil, &streamsSize)
            let streamCount = Int(streamsSize) / MemoryLayout<AudioStreamID>.size
            guard streamCount > 0 else {
                DebugLog.write("AudioMeter.streams scope=\(scope.1) count=0")
                continue
            }
            var streams = [AudioStreamID](repeating: 0, count: streamCount)
            AudioObjectGetPropertyData(device, &streamAddr, 0, nil, &streamsSize, &streams)
            DebugLog.write("AudioMeter.streams scope=\(scope.1) count=\(streamCount) ids=\(streams)")
            for sid in streams {
                var fmt = AudioStreamBasicDescription()
                var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
                var fmtAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioStreamPropertyVirtualFormat,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectGetPropertyData(sid, &fmtAddr, 0, nil, &fmtSize, &fmt)
                DebugLog.write("AudioMeter.stream id=\(sid) rate=\(fmt.mSampleRate) fmtID=\(fmt.mFormatID) flags=\(fmt.mFormatFlags) bytesPerFrame=\(fmt.mBytesPerFrame) channels=\(fmt.mChannelsPerFrame) bits=\(fmt.mBitsPerChannel)")
            }
        }
    }

    private func report(_ msg: String) {
        DebugLog.write("AudioMeter.error \(msg)")
        DispatchQueue.main.async { [weak self] in self?.lastError = msg }
    }

    private func process(_ inputData: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        var sumSquares: Float = 0
        var count: Int = 0
        var peak: Float = 0
        var firstSampleSeen: Float = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let floatCount = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            let ptr = data.assumingMemoryBound(to: Float32.self)
            if floatCount > 0 && firstSampleSeen == 0 { firstSampleSeen = ptr[0] }
            for i in 0..<floatCount {
                let s = ptr[i]
                sumSquares += s * s
                let a = s < 0 ? -s : s
                if a > peak { peak = a }
            }
            count += floatCount
        }
        _ = firstSampleSeen
        let rms = count > 0 ? sqrtf(sumSquares / Float(count)) : 0
        os_unfair_lock_lock(&lock)
        atomicRMS = max(atomicRMS, rms)
        atomicPeak = max(atomicPeak, peak)
        ioProcCallCount &+= 1
        os_unfair_lock_unlock(&lock)
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func tick() {
        os_unfair_lock_lock(&lock)
        let rms = atomicRMS
        let peak = atomicPeak
        let calls = ioProcCallCount
        ioProcCallCount = 0
        atomicRMS = 0
        atomicPeak = 0
        os_unfair_lock_unlock(&lock)

        _ = calls

        let hasSignal = rms != 0 || peak != 0
        if !hasSignal && level == 0 && silentTickCount >= Self.silentPauseThreshold {
            return
        }

        let raw = min(1.0, max(rms * 3.0, peak * 0.7))
        let smoothed = level * 0.55 + raw * 0.45

        ringBuffer[ringHead] = smoothed
        ringHead = (ringHead + 1) % Self.barCount

        let count = Self.barCount
        for i in 0..<count {
            displayBuffer[i] = ringBuffer[(ringHead + i) % count]
        }

        if displayBuffer != bars {
            bars = displayBuffer
        }
        if level != smoothed {
            level = smoothed
        }

        if hasSignal {
            silentTickCount = 0
        } else {
            silentTickCount &+= 1
        }
    }

    private func teardown() {
        if let procID = ioProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
            ioProcID = nil
        }
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        if #available(macOS 14.2, *), tapID != 0 {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = 0
        }
    }

    @available(macOS 14.2, *)
    private func observeProcessListChanges() {
        guard !processListListenerInstalled else { return }
        processListListenerInstalled = true
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyProcessObjectList),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.scheduleRebuild()
            self?.refreshRunningOutputs()
        }
    }

    private func scheduleRebuild() {
        rebuildWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if #available(macOS 14.2, *) { self.setupTap() }
        }
        rebuildWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    @available(macOS 14.2, *)
    private func observeDefaultDeviceChanges() {
        guard !defaultDeviceListenerInstalled else { return }
        defaultDeviceListenerInstalled = true
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            DispatchQueue.main
        ) { [weak self] _, _ in
            guard let self else { return }
            let newUID = self.defaultOutputUID()
            if newUID != self.currentOutputUID {
                self.setupTap()
            }
        }
    }

    private func readCFStringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let err = withUnsafeMutablePointer(to: &cf) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, UnsafeMutableRawPointer(ptr))
        }
        guard err == noErr, let unmanaged = cf else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    @available(macOS 14.2, *)
    private func scheduleSourcePolling() {
        sourceTimer?.invalidate()
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshSources()
        }
        RunLoop.main.add(t, forMode: .common)
        sourceTimer = t
        refreshSources()
    }

    @available(macOS 14.2, *)
    private func refreshSources() {
        let processes = audioProcessObjectIDs()
        var collected: [SourceApp] = []
        for obj in processes {
            guard isProcessRunningOutput(obj) else { continue }
            guard let pid = pidForAudioProcess(obj),
                  let app = NSRunningApplication(processIdentifier: pid) else { continue }
            let id = app.bundleIdentifier ?? "pid:\(pid)"
            let name = app.localizedName ?? id
            if !collected.contains(where: { $0.id == id }) {
                collected.append(SourceApp(id: id, name: name, icon: app.icon))
            }
        }
        if collected != activeSources {
            activeSources = collected
        }
        refreshRunningOutputs()
    }

    private func isProcessRunningOutput(_ id: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyIsRunningOutput),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &running)
        return err == noErr && running != 0
    }

    private func pidForAudioProcess(_ id: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioProcessPropertyPID),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let err = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &pid)
        return (err == noErr && pid > 0) ? pid : nil
    }

    private func audioProcessObjectIDs() -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyProcessObjectList),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr,
              size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var ids = [AudioObjectID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }
        var ownPID: pid_t = ProcessInfo.processInfo.processIdentifier
        var ownObject: AudioObjectID = 0
        var pidAddr = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyTranslatePIDToProcessObject),
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var outSize = UInt32(MemoryLayout<AudioObjectID>.size)
        _ = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &pidAddr,
            UInt32(MemoryLayout<pid_t>.size),
            &ownPID,
            &outSize,
            &ownObject
        )
        return ids.filter { $0 != 0 && $0 != ownObject }
    }

    private func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else {
            return nil
        }
        return readCFStringProperty(id, kAudioDevicePropertyDeviceUID)
    }
}
