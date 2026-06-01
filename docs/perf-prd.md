# Sift performance backlog

A prioritized, non-breaking performance backlog. Each item is small and mechanical — current behavior preserved.

**Execution model**: sequential. Each item gets a focused sub-agent, builds clean, and is presented as a diff for the user to commit. The user holds the commit pen.

**Order is ROI-first**: items at the top are the highest-leverage per-keystroke / per-frame wins. Tickbox to track progress.

---

## P0 — per-keystroke hot path

### [x] 1. Gate `DebugLog.write` so it's a no-op outside debug builds
- **Where**: `Sources/Sift/DebugLog.swift` plus the 6 callers in `SearchField.swift`, 2 in `SiftView.swift`, 3 in `BookmarkView.swift`, 1 in `AppDelegate.swift`. (Setup-time calls in `AudioMeterService.swift` are cold-path and can stay.)
- **Current**: every call opens `/tmp/sift-debug.log`, seeks to end, writes, closes. At least 5 syscalls fire per keystroke even when nobody's reading the log.
- **Target**: in release / production runs, `DebugLog.write` returns immediately. Optionally controllable via an env var (e.g. `SIFT_DEBUG=1`) so the user can still tail the log when needed.
- **Acceptance**: `swift build -c release` produces a binary with no measurable file I/O from keystrokes; setting `SIFT_DEBUG=1` restores logging.
- **Blast radius**: tiny — internal logging only.
- **Est**: 15 min.

### [x] 2. Debounce `SiftViewModel.updateQuery` by ~40 ms
- **Where**: `Sources/Sift/SiftView.swift` (`updateQuery` + its `SearchField` binding around `SiftView.body`).
- **Current**: every keystroke synchronously fuzzy-matches over apps + bookmarks + devices + sleep + screenshot, sorts, slices. Fast typists eat the full cost on every key.
- **Target**: keystrokes update the `query` `@Published` immediately (so the field stays responsive), but the heavy `merged` build is debounced to fire ~40 ms after typing stops. Cancel any in-flight pending search on a new keystroke.
- **Acceptance**: typing "github" or "screenshot" feels smooth; final results identical to today; no visible flicker on slow typing because the field is decoupled from the search.
- **Blast radius**: small — only timing of search.
- **Est**: 30 min.

### [x] 3. Precompute `searchableApps` instead of filtering per keystroke
- **Where**: `Sources/Sift/SiftView.swift:268`.
- **Current**: `allApps.filter { !disabledIDs.contains($0.id) }` allocates a fresh array on every keystroke.
- **Target**: maintain `searchableApps` on the view-model; recompute only on `reload()` (or whenever the disabled set or app index changes).
- **Acceptance**: query results identical; no per-keystroke allocation for the apps filter.
- **Blast radius**: tiny.
- **Est**: 15 min.

### [x] 4. Memoize `highlightedName` per result instead of rebuilding `AttributedString` on every render
- **Where**: `Sources/Sift/SiftView.swift` (`ResultRow.highlightedName`) and the `Result` enum.
- **Current**: each `ResultRow.body` reruns `FuzzyMatcher.matchedIndices(query:candidate:)` and walks the candidate char-by-char to build an `AttributedString`. Every selection arrow keypress re-renders all rows in the LazyVStack, redoing this work.
- **Target**: compute the highlighted attributed string once when the result is built in `updateQuery` and stash it on each `Result` variant (or on a parallel array). The view just reads it.
- **Acceptance**: highlights look identical; arrow-key navigation no longer re-runs `matchedIndices` per row.
- **Blast radius**: small.
- **Est**: 45 min.

---

## P1 — per-frame / per-event

### [x] 5. Cap audio meter to ~20 fps and use a ring buffer instead of reallocating `bars`
- **Where**: `Sources/Sift/AudioMeterService.swift` (`tick`, `bars`, `refreshTimer`).
- **Current**: 30 fps timer reallocates a `[Float]`, shifts 9 elements left, publishes — invalidating the visualizer every tick regardless of audio state.
- **Target**: drop timer to ~20 fps; write into a fixed-size ring buffer indexed by a write head; publish only the array via a computed slice or rebuild only when the head wraps. Optionally pause the publishing path entirely when rms+peak have been zero for >1 s (still drain IOProc samples so the next ramp-up is instant).
- **Acceptance**: visualizer visually identical at normal volumes; CPU profile shows fewer SwiftUI invalidations; no allocations in the hot tick path.
- **Blast radius**: small — purely internal.
- **Est**: 45 min.

### [x] 6. Cache `AudioService.isRunning` inside `AudioMeterService` and read from there in the status strip
- **Where**: `Sources/Sift/SiftView.swift:249` (`recomputeVisibleStatusDevices`), `Sources/Sift/AudioMeterService.swift`, `Sources/Sift/AudioService.swift`.
- **Current**: `recomputeVisibleStatusDevices` synchronously queries CoreAudio's `kAudioDevicePropertyDeviceIsRunningSomewhere` for each visible device on every panel open and every devices refresh.
- **Target**: `AudioMeterService` already listens for default-output and process-list changes. Have it also track which audio-output device IDs are currently producing audio (using its tap + a property listener on `kAudioDevicePropertyDeviceIsRunningSomewhere`). `recomputeVisibleStatusDevices` reads from this cached set.
- **Acceptance**: status strip shows the same devices; CoreAudio property reads only happen on actual change events.
- **Blast radius**: small — internal data flow.
- **Est**: 1 h.

### [x] 7. Cache `NSRunningApplication` lookups by PID in `refreshSources`
- **Where**: `Sources/Sift/AudioMeterService.swift:280-318`.
- **Current**: every 1.5 s timer poll calls `NSRunningApplication(processIdentifier:)` for every audio-producing process, re-allocating + re-resolving even when the set hasn't changed.
- **Target**: maintain a `[pid_t: SourceApp]` cache. The process-list `AudioObjectAddPropertyListenerBlock` already fires when processes appear/disappear — invalidate then. The poll timer can drop to ~5 s (or be removed entirely once we trust the listener).
- **Acceptance**: source pills update as quickly as they do today when an app starts/stops audio; no per-second TCC-touching lookups.
- **Blast radius**: small.
- **Est**: 30 min.

### [x] 8. Reuse the backdrop window across panel opens
- **Where**: `Sources/Sift/PanelPlacement.swift` (`presentBackdrop`), `Sources/Sift/BackdropWindow.swift`.
- **Current**: every ⌘-Space tears down the previous backdrop window and builds a new `NSHostingView<PsychedelicView>` with a freshly-allocated random effect.
- **Target**: keep one `BackdropWindow` per screen and reorder it in/out; only swap the psychedelic effect when the user wants a new random pick (e.g. once per `show()`). Reusing the host view avoids the allocation cost of effect initializers (Confetti, Plasma, Starfield are not cheap).
- **Acceptance**: opening the panel feels snappier; backdrop appears/dismisses identically.
- **Blast radius**: medium — needs care around screen changes and the random-effect-on-each-open contract.
- **Est**: 1 h.

---

## P2 — quality of life

### [x] 9. `FaviconCache.pendingHosts` → `Set<String>` for O(1) dedup
- **Where**: `Sources/Sift/FaviconCache.swift:86`.
- **Current**: `pendingHosts.contains(where:)` is O(n); `prefetch` walks all bookmarks, so prefetch is O(n²) on bookmark count.
- **Target**: store as `Set<String>`; update enqueue and dequeue accordingly.
- **Acceptance**: prefetch on a 500-bookmark vault stops being measurably slow; favicons load identically.
- **Blast radius**: tiny.
- **Est**: 15 min.

### [x] 10. Move `AppIndex.scan` off the main thread in `SettingsViewModel.init`
- **Where**: `Sources/Sift/SettingsView.swift:67`.
- **Current**: synchronously scans every app directory during settings-window construction.
- **Target**: kick off a `Task.detached(priority: .utility)`; publish `apps` when ready, mirroring `SiftViewModel.refreshIndex`. Show a small "loading…" placeholder during the brief gap.
- **Acceptance**: opening Settings is instant; app list eventually populates.
- **Blast radius**: small.
- **Est**: 30 min.

### [x] 11. Persist `AppIconCache` to disk so cold launches don't re-fetch
- **Where**: `Sources/Sift/AppIconCache.swift`.
- **Current**: in-memory only; first launch (and every relaunch) round-trips to `.app` bundles for every icon as the user scrolls/types.
- **Target**: write a PNG (or system-format) per `bundleID` into `~/Library/Caches/Sift/icons/`; load eagerly on launch into the memory cache. Invalidate on bundle modification date change.
- **Acceptance**: relaunch shows icons immediately; modified apps still pick up new icons.
- **Blast radius**: small — read-through cache.
- **Est**: 1 h.

### [x] 12. Lower `PsychedelicView` redraw rate when intensity is low
- **Where**: `Sources/Sift/PsychedelicView.swift` (each effect's `TimelineView`).
- **Current**: every effect uses `TimelineView(.animation)`, redrawing at the display refresh rate (often 120 Hz) regardless of `intensity`.
- **Target**: switch to `.periodic(from:by:)` ~30 fps when intensity < 0.5; skip rendering entirely if intensity < 0.05.
- **Acceptance**: effects look the same; backdrop CPU drops at low intensity settings.
- **Blast radius**: small.
- **Est**: 30 min.

### [x] 13. `NowPlayingService.refresh` — only invoke `getInfo` when the playback state changes
- **Where**: `Sources/Sift/NowPlayingService.swift:66-102`.
- **Current**: every observed MediaRemote notification fires all three callbacks; equality guards prevent SwiftUI re-renders but the dict allocation still happens.
- **Target**: track which notification fired and only call the relevant accessor (`isPlaying` for the play-state-change notification, `getInfo` for the info-change notification, `getPID` for the application-change notification).
- **Acceptance**: track + source pill behavior unchanged; fewer wasted MediaRemote calls.
- **Blast radius**: small.
- **Est**: 30 min.

### [x] 14. Stop reassigning `SearchField` closures every `updateNSView`
- **Where**: `Sources/Sift/SearchField.swift:43-58`.
- **Current**: each SwiftUI update reassigns six closures on the text field, allocating new captures.
- **Target**: store the closures once on the coordinator and forward through it; only update when the actual closure identity changes (rare).
- **Acceptance**: search field behaves identically; fewer per-render allocations.
- **Blast radius**: tiny.
- **Est**: 15 min.

---

## Out of scope (for now)

- App-level refactors that change UX (e.g. async result rendering with progress).
- New features.
- Removing the menubar popover or other surface-level changes.

---

## Notes for sub-agents

- Build via `just build`. Don't skip the bundle step (audio capture entitlement is part of the bundle plist).
- After your change, return a 2–4 sentence summary: what changed, files touched, build result.
- Do **not** commit. The user owns commits.
- If a change has any user-visible risk (Item 8 in particular), flag it explicitly so the user can decide whether to ship.
