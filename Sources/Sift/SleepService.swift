import Foundation

@MainActor
final class SleepService {
    static let shared = SleepService()

    private(set) var isDisabled: Bool = false
    var onStateChange: (() -> Void)?

    private static let pmsetPlistPath = "/Library/Preferences/com.apple.PowerManagement.plist"
    private var fileWatcherSource: DispatchSourceFileSystemObject?

    private init() {}

    func startWatching() {
        refresh()
        setupFileWatcher()
    }

    private func setupFileWatcher() {
        fileWatcherSource?.cancel()
        let fd = open(Self.pmsetPlistPath, O_EVTONLY)
        guard fd >= 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.setupFileWatcher()
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.refresh()
            let events = source.data
            if events.contains(.delete) || events.contains(.rename) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.setupFileWatcher()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        fileWatcherSource = source
    }

    func refresh() {
        Task.detached(priority: .utility) {
            let output = SleepService.runShellStatic("/usr/bin/pmset", ["-g"])
            let disabled = SleepService.parseDisabled(output: output)
            await MainActor.run { [weak self] in
                guard let self else { return }
                let changed = disabled != self.isDisabled
                self.isDisabled = disabled
                if changed { self.onStateChange?() }
            }
        }
    }

    nonisolated static func runShellStatic(_ executable: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @discardableResult
    func enable() -> Bool {
        let exit = runShellExit("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "0"])
        if exit == 0 {
            let changed = isDisabled != false
            isDisabled = false
            if changed { onStateChange?() }
            return true
        }
        return false
    }

    @discardableResult
    func disable() -> Bool {
        let exit = runShellExit("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "disablesleep", "1"])
        if exit == 0 {
            let changed = isDisabled != true
            isDisabled = true
            if changed { onStateChange?() }
            return true
        }
        return false
    }

    nonisolated private static func parseDisabled(output: String) -> Bool {
        for line in output.components(separatedBy: "\n") {
            let lower = line.lowercased()
            if lower.contains("sleepdisabled") || lower.contains("disablesleep") {
                return line.trimmingCharacters(in: .whitespaces).hasSuffix("1")
            }
        }
        return false
    }

    private func runShellExit(_ executable: String, _ args: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = args
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return -1 }
        task.waitUntilExit()
        return task.terminationStatus
    }
}

enum SleepCommand: Hashable, Identifiable {
    case enable
    case disable

    var id: String {
        switch self {
        case .enable: return "sleep:enable"
        case .disable: return "sleep:disable"
        }
    }

    var name: String {
        switch self {
        case .enable: return "Enable sleep"
        case .disable: return "Disable sleep"
        }
    }

    var systemImage: String {
        switch self {
        case .enable: return "moon.zzz"
        case .disable: return "eye.fill"
        }
    }

    static func available(isDisabled: Bool) -> [SleepCommand] {
        isDisabled ? [.enable] : [.disable]
    }

    @MainActor
    func perform() {
        switch self {
        case .enable: SleepService.shared.enable()
        case .disable: SleepService.shared.disable()
        }
    }
}
