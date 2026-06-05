import Foundation
import CoreAudio
import AppKit
import Accelerate
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

    private struct TapEntry {
        let pid: pid_t
        let audioObjectID: AudioObjectID
        let tapID: AudioObjectID
        let tapUID: String
    }

    private struct BufferSlice {
        let start: Int
        let count: Int
    }

    private var taps: [TapEntry] = []
    private var aggregateID: AudioDeviceID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var currentOutputUID: String?

    private var lock = os_unfair_lock_s()
    private var atomicRMSSq: [Float] = []
    private var atomicSamples: [Int] = []
    private var atomicPeak: [Float] = []
    private var ioProcCallCount: Int = 0

    private var lastAudibleAt: [pid_t: TimeInterval] = [:]
    private static let audibilityThreshold: Float = 0.0015
    private static let audibilityWindowSec: TimeInterval = 0.6

    private var refreshTimer: Timer?
    private var sourceTimer: Timer?
    private var defaultDeviceListenerInstalled = false
    private var processListListenerInstalled = false
    private var rebuildWorkItem: DispatchWorkItem?

    private var sourceCache: [pid_t: SourceApp] = [:]

    private var ringBuffer: [Float] = Array(repeating: 0, count: barCount)
    private var ringHead: Int = 0
    private var displayBuffer: [Float] = Array(repeating: 0, count: barCount)
    private var silentTickCount: Int = 0
    private static let silentPauseThreshold: Int = 20

    private var agcEnvelope: Float = 0.1
    private static let agcAttack: Float = 0.35
    private static let agcRelease: Float = 0.004
    private static let agcFloor: Float = 0.04
    private static let agcTarget: Float = 0.78

    private var isRunning = false

    private init() {}

    func start() {
        guard !isRunning else { DebugLog.write("AudioMeter.start ignored (already running)"); return }
        DebugLog.write("AudioMeter.start")
        isRunning = true
        if #available(macOS 14.2, *) {
            setupTap()
            observeDefaultDeviceChanges()
            observeProcessListChanges()
            scheduleSourcePolling()
        }
        scheduleRefresh()
        refreshRunningOutputs()
    }

    func stop() {
        guard isRunning else { DebugLog.write("AudioMeter.stop ignored (not running)"); return }
        DebugLog.write("AudioMeter.stop tapsBeforeTeardown=\(taps.count) aggregateID=\(aggregateID)")
        isRunning = false
        rebuildWorkItem?.cancel()
        rebuildWorkItem = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        sourceTimer?.invalidate()
        sourceTimer = nil
        teardown()
        currentOutputUID = nil
        sourceCache = [:]
        lastAudibleAt = [:]
        silentTickCount = 0
        agcEnvelope = 0.1
        ringBuffer = Array(repeating: 0, count: Self.barCount)
        ringHead = 0
        displayBuffer = Array(repeating: 0, count: Self.barCount)
        let cleared: [Float] = Array(repeating: 0, count: Self.barCount)
        if bars != cleared { bars = cleared }
        if level != 0 { level = 0 }
        if isAvailable { isAvailable = false }
        if !activeSources.isEmpty { activeSources = [] }
        if !runningOutputDeviceIDs.isEmpty { runningOutputDeviceIDs = [] }
        lastError = nil
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

        let processObjects = audioProcessObjectIDs()
        DebugLog.write("AudioMeter.audioProcesses count=\(processObjects.count) ids=\(processObjects)")

        var newTaps: [TapEntry] = []
        for obj in processObjects {
            guard let pid = pidForAudioProcess(obj) else { continue }
            let desc = CATapDescription(stereoMixdownOfProcesses: [obj])
            desc.uuid = UUID()
            desc.isPrivate = false
            desc.isExclusive = false
            desc.muteBehavior = .unmuted
            desc.name = "SiftVisualizerTap.pid\(pid)"

            var tap: AudioObjectID = 0
            let tapErr = AudioHardwareCreateProcessTap(desc, &tap)
            guard tapErr == noErr, tap != 0 else {
                DebugLog.write("AudioMeter.createTap pid=\(pid) err=\(tapErr) skipped")
                continue
            }
            guard let tapUID = readCFStringProperty(tap, kAudioTapPropertyUID) else {
                DebugLog.write("AudioMeter.tapUIDRead pid=\(pid) failed; destroying tap")
                AudioHardwareDestroyProcessTap(tap)
                continue
            }
            newTaps.append(TapEntry(pid: pid, audioObjectID: obj, tapID: tap, tapUID: tapUID))
        }

        guard !newTaps.isEmpty else {
            report("no audio processes to tap")
            return
        }
        taps = newTaps
        atomicRMSSq = [Float](repeating: 0, count: newTaps.count)
        atomicSamples = [Int](repeating: 0, count: newTaps.count)
        atomicPeak = [Float](repeating: 0, count: newTaps.count)
        DebugLog.write("AudioMeter.createdTaps count=\(newTaps.count) pids=\(newTaps.map { $0.pid })")

        let aggregateUID = "io.sift.visualizer.\(ProcessInfo.processInfo.processIdentifier).\(UInt64.random(in: 0..<UInt64.max))"
        let subTapList: [[String: Any]] = newTaps.map { entry in
            [
                kAudioSubTapUIDKey: entry.tapUID,
                kAudioSubTapDriftCompensationKey: 1
            ] as [String: Any]
        }
        let aggregateDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sift Aggregate",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapListKey: subTapList
        ]
        var agg: AudioDeviceID = 0
        let aggErr = AudioHardwareCreateAggregateDevice(aggregateDict as CFDictionary, &agg)
        DebugLog.write("AudioMeter.createAggregate err=\(aggErr) id=\(agg) outputUID=\(outputUID) tapCount=\(newTaps.count)")
        guard aggErr == noErr, agg != 0 else {
            report("aggregate create failed: OSStatus \(aggErr)")
            teardown()
            return
        }
        aggregateID = agg

        let slices = computeBufferSlices(device: agg, expectedStreamCount: newTaps.count)
        DebugLog.write("AudioMeter.bufferSlices \(slices.map { "[\($0.start),\($0.count)]" }.joined(separator: ","))")

        var procID: AudioDeviceIOProcID?
        let installErr = AudioDeviceCreateIOProcIDWithBlock(&procID, agg, nil) { [weak self] _, inputData, _, _, _ in
            self?.process(inputData, slices: slices)
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

    private func computeBufferSlices(device: AudioDeviceID, expectedStreamCount: Int) -> [BufferSlice] {
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(device, &streamAddr, 0, nil, &streamsSize)
        let streamCount = Int(streamsSize) / MemoryLayout<AudioStreamID>.size
        guard streamCount > 0 else { return [] }
        var streams = [AudioStreamID](repeating: 0, count: streamCount)
        AudioObjectGetPropertyData(device, &streamAddr, 0, nil, &streamsSize, &streams)

        var perStreamBufferCount: [Int] = []
        for sid in streams {
            var fmt = AudioStreamBasicDescription()
            var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var fmtAddr = AudioObjectPropertyAddress(
                mSelector: kAudioStreamPropertyVirtualFormat,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectGetPropertyData(sid, &fmtAddr, 0, nil, &fmtSize, &fmt)
            let isNonInterleaved = (fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
            let bufCount = isNonInterleaved ? max(1, Int(fmt.mChannelsPerFrame)) : 1
            perStreamBufferCount.append(bufCount)
        }
        if perStreamBufferCount.count != expectedStreamCount {
            DebugLog.write("AudioMeter.bufferSliceWarn expected=\(expectedStreamCount) actualStreams=\(perStreamBufferCount.count)")
        }
        var slices: [BufferSlice] = []
        var cursor = 0
        for i in 0..<expectedStreamCount {
            let c = i < perStreamBufferCount.count ? perStreamBufferCount[i] : 1
            slices.append(BufferSlice(start: cursor, count: c))
            cursor += c
        }
        return slices
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

    private func process(_ inputData: UnsafePointer<AudioBufferList>, slices: [BufferSlice]) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        let totalBuffers = buffers.count

        var localSumSq = [Float](repeating: 0, count: slices.count)
        var localSamples = [Int](repeating: 0, count: slices.count)
        var localPeak = [Float](repeating: 0, count: slices.count)

        for (i, slice) in slices.enumerated() {
            for j in 0..<slice.count {
                let idx = slice.start + j
                guard idx < totalBuffers else { break }
                let buffer = buffers[idx]
                guard let data = buffer.mData else { continue }
                let floatCount = vDSP_Length(buffer.mDataByteSize) / vDSP_Length(MemoryLayout<Float32>.size)
                guard floatCount > 0 else { continue }
                let ptr = data.assumingMemoryBound(to: Float32.self)
                var bufSumSq: Float = 0
                vDSP_measqv(ptr, 1, &bufSumSq, floatCount)
                localSumSq[i] += bufSumSq * Float(floatCount)
                var bufPeak: Float = 0
                vDSP_maxmgv(ptr, 1, &bufPeak, floatCount)
                if bufPeak > localPeak[i] { localPeak[i] = bufPeak }
                localSamples[i] += Int(floatCount)
            }
        }

        os_unfair_lock_lock(&lock)
        let upper = min(slices.count, atomicRMSSq.count)
        for i in 0..<upper {
            atomicRMSSq[i] += localSumSq[i]
            atomicSamples[i] += localSamples[i]
            if localPeak[i] > atomicPeak[i] { atomicPeak[i] = localPeak[i] }
        }
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
        let sumSqs = atomicRMSSq
        let samples = atomicSamples
        let peaks = atomicPeak
        let calls = ioProcCallCount
        ioProcCallCount = 0
        for i in 0..<atomicRMSSq.count {
            atomicRMSSq[i] = 0
            atomicSamples[i] = 0
            atomicPeak[i] = 0
        }
        let tapsSnapshot = taps
        os_unfair_lock_unlock(&lock)

        _ = calls

        let now = CACurrentMediaTime()
        var mixRMS: Float = 0
        var mixPeak: Float = 0
        let limit = min(tapsSnapshot.count, sumSqs.count)
        for i in 0..<limit {
            let n = samples[i]
            let rmsI = n > 0 ? sqrtf(sumSqs[i] / Float(n)) : 0
            let peakI = peaks[i]
            if peakI >= Self.audibilityThreshold || rmsI >= Self.audibilityThreshold * 0.5 {
                lastAudibleAt[tapsSnapshot[i].pid] = now
            }
            mixRMS = max(mixRMS, rmsI)
            mixPeak = max(mixPeak, peakI)
        }

        refreshAudibleSources(now: now)
        let hasSignal = mixRMS != 0 || mixPeak != 0
        if !hasSignal && level == 0 && silentTickCount >= Self.silentPauseThreshold {
            return
        }

        let combined = max(mixRMS * 2.5, mixPeak)
        let coeff: Float = combined > agcEnvelope ? Self.agcAttack : Self.agcRelease
        agcEnvelope += (combined - agcEnvelope) * coeff
        let denom = max(agcEnvelope, Self.agcFloor)
        let raw = min(1.0, max(0.0, (combined / denom) * Self.agcTarget))
        let smoothed = raw > level
            ? level * 0.35 + raw * 0.65
            : level * 0.7 + raw * 0.3

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
        if #available(macOS 14.2, *) {
            for entry in taps where entry.tapID != 0 {
                AudioHardwareDestroyProcessTap(entry.tapID)
            }
        }
        os_unfair_lock_lock(&lock)
        taps = []
        atomicRMSSq = []
        atomicSamples = []
        atomicPeak = []
        os_unfair_lock_unlock(&lock)
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
            guard let self, self.isRunning else { return }
            self.scheduleRebuild()
            self.refreshRunningOutputs()
            self.refreshSources()
        }
    }

    private func scheduleRebuild() {
        guard isRunning else { return }
        rebuildWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning else { return }
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
            guard let self, self.isRunning else { return }
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
        let t = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshSources()
        }
        RunLoop.main.add(t, forMode: .common)
        sourceTimer = t
        refreshSources()
    }

    @available(macOS 14.2, *)
    private func refreshSources() {
        let processes = audioProcessObjectIDs()
        var livePIDs: Set<pid_t> = []
        for obj in processes {
            if let pid = pidForAudioProcess(obj) { livePIDs.insert(pid) }
        }
        sourceCache = sourceCache.filter { livePIDs.contains($0.key) }
        lastAudibleAt = lastAudibleAt.filter { livePIDs.contains($0.key) }
        refreshRunningOutputs()
        _ = refreshAudibleSources(now: CACurrentMediaTime())
    }

    @discardableResult
    private func refreshAudibleSources(now: TimeInterval) -> Bool {
        let cutoff = now - Self.audibilityWindowSec
        var collected: [SourceApp] = []
        for (pid, ts) in lastAudibleAt where ts >= cutoff {
            let source: SourceApp
            if let cached = sourceCache[pid] {
                source = cached
            } else {
                guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
                let id = app.bundleIdentifier ?? "pid:\(pid)"
                let name = app.localizedName ?? id
                source = SourceApp(id: id, name: name, icon: app.icon)
                sourceCache[pid] = source
            }
            if !collected.contains(where: { $0.id == source.id }) {
                collected.append(source)
            }
        }
        collected.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if collected != activeSources {
            activeSources = collected
            return true
        }
        return false
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
