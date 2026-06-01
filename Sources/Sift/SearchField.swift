import AppKit
import SwiftUI

final class KeyHandlingTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onMoveRight: (() -> Void)?
    var onMoveLeft: (() -> Bool)?
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void
    var onMoveRight: (() -> Void)? = nil
    var onMoveLeft: (() -> Bool)? = nil

    func makeNSView(context: Context) -> KeyHandlingTextField {
        DebugLog.write("SearchField.makeNSView")
        let field = KeyHandlingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .light)
        field.placeholderString = "Sift..."
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = context.coordinator
        let coord = context.coordinator
        coord.onMoveUp = onMoveUp
        coord.onMoveDown = onMoveDown
        coord.onSubmit = onSubmit
        coord.onCancel = onCancel
        coord.onMoveRight = onMoveRight
        coord.onMoveLeft = onMoveLeft
        field.onMoveUp = { [weak coord] in coord?.onMoveUp?() }
        field.onMoveDown = { [weak coord] in coord?.onMoveDown?() }
        field.onSubmit = { [weak coord] in coord?.onSubmit?() }
        field.onCancel = { [weak coord] in coord?.onCancel?() }
        field.onMoveRight = { [weak coord] in coord?.onMoveRight?() }
        field.onMoveLeft = { [weak coord] in coord?.onMoveLeft?() ?? false }
        return field
    }

    func updateNSView(_ nsView: KeyHandlingTextField, context: Context) {
        DebugLog.write("SearchField.updateNSView field='\(nsView.stringValue)' text='\(text)' focus=\(focusToken)")
        let coord = context.coordinator
        coord.onMoveUp = onMoveUp
        coord.onMoveDown = onMoveDown
        coord.onSubmit = onSubmit
        coord.onCancel = onCancel
        coord.onMoveRight = onMoveRight
        coord.onMoveLeft = onMoveLeft
        if nsView.stringValue != text { nsView.stringValue = text }
        if coord.lastFocusToken != focusToken {
            coord.lastFocusToken = focusToken
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                nsView.currentEditor()?.selectedRange = NSRange(location: nsView.stringValue.count, length: 0)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        DebugLog.write("SearchField.makeCoordinator")
        return Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        var lastFocusToken = -1
        var onMoveUp: (() -> Void)?
        var onMoveDown: (() -> Void)?
        var onSubmit: (() -> Void)?
        var onCancel: (() -> Void)?
        var onMoveRight: (() -> Void)?
        var onMoveLeft: (() -> Bool)?

        init(text: Binding<String>) {
            _text = text
            super.init()
            DebugLog.write("SearchField.Coordinator.init")
        }

        deinit {
            DebugLog.write("SearchField.Coordinator.deinit")
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            DebugLog.write("SearchField.controlTextDidChange '\(field.stringValue)'")
            text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard let field = control as? KeyHandlingTextField else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMoveUp?()
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMoveDown?()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                onSubmit?()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel?()
                return true
            case #selector(NSResponder.moveRight(_:)):
                let length = field.stringValue.count
                let position = textView.selectedRange().location
                if position >= length, let handler = onMoveRight {
                    handler()
                    return true
                }
                return false
            case #selector(NSResponder.moveLeft(_:)):
                if let handler = onMoveLeft, handler() {
                    return true
                }
                return false
            default:
                return false
            }
        }
    }
}
