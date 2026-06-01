import AppKit
import Foundation

@MainActor
final class ScreenshotController {
    static let shared = ScreenshotController()

    private var markupController: MarkupWindowController?

    private init() {}

    func captureRegion() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sift-shot-\(UUID().uuidString).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-t", "png", url.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return
        }

        guard FileManager.default.fileExists(atPath: url.path),
              let image = NSImage(contentsOf: url) else {
            return
        }
        try? FileManager.default.removeItem(at: url)

        present(image: image)
    }

    private func present(image: NSImage) {
        let controller = MarkupWindowController(image: image) { [weak self] annotated in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([annotated])
            self?.dismiss()
        } onCancel: { [weak self] in
            self?.dismiss()
        }
        controller.show()
        markupController = controller
    }

    private func dismiss() {
        markupController?.close()
        markupController = nil
    }
}
