import Foundation
import AppKit

@MainActor
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    struct Info: Equatable {
        var title: String
        var artist: String?
    }

    struct Source: Equatable {
        var name: String
        var bundleID: String?
    }

    @Published private(set) var info: Info?
    @Published private(set) var source: Source?
    @Published private(set) var isPlaying: Bool = false

    private typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping (CFDictionary) -> Void) -> Void
    private typealias GetIsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    private typealias GetPIDFn = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    private typealias RegisterFn = @convention(c) (DispatchQueue) -> Void

    private let getInfo: GetInfoFn?
    private let getIsPlaying: GetIsPlayingFn?
    private let getPID: GetPIDFn?

    private init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        if let handle,
           let infoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo"),
           let playSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
           let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            getInfo = unsafeBitCast(infoSym, to: GetInfoFn.self)
            getIsPlaying = unsafeBitCast(playSym, to: GetIsPlayingFn.self)
            let register = unsafeBitCast(regSym, to: RegisterFn.self)
            register(DispatchQueue.main)
        } else {
            getInfo = nil
            getIsPlaying = nil
        }
        if let handle, let pidSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            getPID = unsafeBitCast(pidSym, to: GetPIDFn.self)
        } else {
            getPID = nil
        }

        let nc = NotificationCenter.default
        nc.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshInfo() }
        }
        nc.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshIsPlaying() }
        }
        nc.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshIsPlaying() }
        }
        nc.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshSource() }
        }
        refresh()
    }

    func refresh() {
        refreshInfo()
        refreshIsPlaying()
        refreshSource()
    }

    func refreshIsPlaying() {
        getIsPlaying?(DispatchQueue.main) { [weak self] playing in
            Task { @MainActor in
                guard let self else { return }
                if self.isPlaying != playing { self.isPlaying = playing }
            }
        }
    }

    func refreshInfo() {
        getInfo?(DispatchQueue.main) { [weak self] raw in
            let dict = raw as? [String: Any] ?? [:]
            let title = (dict["kMRMediaRemoteNowPlayingInfoTitle"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let artist = (dict["kMRMediaRemoteNowPlayingInfoArtist"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let next: Info? = title.isEmpty
                ? nil
                : Info(title: title, artist: artist.isEmpty ? nil : artist)
            Task { @MainActor in
                guard let self else { return }
                if self.info != next { self.info = next }
            }
        }
    }

    func refreshSource() {
        getPID?(DispatchQueue.main) { [weak self] pid in
            Task { @MainActor in
                guard let self else { return }
                let next: Source?
                if pid > 0, let app = NSRunningApplication(processIdentifier: pid) {
                    next = Source(
                        name: app.localizedName ?? app.bundleIdentifier ?? "Audio",
                        bundleID: app.bundleIdentifier
                    )
                } else {
                    next = nil
                }
                if self.source != next { self.source = next }
            }
        }
    }
}
