import AppKit
import SwiftUI

final class KeyHandlingTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> KeyHandlingTextField {
        DebugLog.write("SearchField.makeNSView")
        let field = KeyHandlingTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 24, weight: .light)
        field.placeholderString = "Search"
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.delegate = context.coordinator
        field.onMoveUp = onMoveUp
        field.onMoveDown = onMoveDown
        field.onSubmit = onSubmit
        field.onCancel = onCancel
        return field
    }

    func updateNSView(_ nsView: KeyHandlingTextField, context: Context) {
        DebugLog.write("SearchField.updateNSView field='\(nsView.stringValue)' text='\(text)' focus=\(focusToken)")
        if nsView.stringValue != text { nsView.stringValue = text }
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
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
                field.onMoveUp?()
                return true
            case #selector(NSResponder.moveDown(_:)):
                field.onMoveDown?()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                field.onSubmit?()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                field.onCancel?()
                return true
            default:
                return false
            }
        }
    }
}
