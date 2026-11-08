import SwiftUI
import UIKit

// A tiny, transparent responder opens the system keyboard over the game. The
// game stays visible; committed text goes straight to its focused text field.
struct GameKeyboardCapture: UIViewRepresentable {
    let onClose: () -> Void
    func makeUIView(context: Context) -> GameKeyboardTextView {
        let view = GameKeyboardTextView(frame: .zero, textContainer: nil)
        view.onClose = onClose
        return view
    }
    func updateUIView(_ view: GameKeyboardTextView, context: Context) { view.onClose = onClose }
    static func dismantleUIView(_ view: GameKeyboardTextView, coordinator: ()) { view.dismissKeyboard(notify: false) }
}

final class GameKeyboardTextView: UITextView, UITextViewDelegate {
    var onClose: (() -> Void)?
    private var closing = false
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self
        backgroundColor = .clear; textColor = .clear; tintColor = .clear
        isScrollEnabled = false
        accessibilityLabel = "Game keyboard"
        autocapitalizationType = .none; autocorrectionType = .no; spellCheckingType = .no
        smartQuotesType = .no; smartDashesType = .no; smartInsertDeleteType = .no
        keyboardAppearance = .dark
        let bar = UIToolbar(frame: CGRect(x: 0, y: 0, width: 320, height: 40))
        bar.items = [
            UIBarButtonItem(title: "Esc", style: .plain, target: self, action: #selector(pressEscape)),
            UIBarButtonItem(title: "Tab", style: .plain, target: self, action: #selector(pressTab)),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            UIBarButtonItem(title: "Paste", style: .plain, target: self, action: #selector(pasteText)),
            UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(closeKeyboard)),
        ]
        inputAccessoryView = bar
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.window != nil, !self.closing else { return }
                self.becomeFirstResponder()
            }
        }
    }
    func textViewDidChange(_ textView: UITextView) {
        // Keep marked text local until the system IME commits it. Forwarding
        // every intermediate composition would duplicate characters in-game.
        guard markedTextRange == nil, !text.isEmpty else { return }
        let committed = text ?? ""
        text = ""
        _ = GameInput.text(committed)
    }
    override func deleteBackward() {
        if markedTextRange == nil && text.isEmpty {
            GameInput.key("Backspace", pressed: true); GameInput.key("Backspace", pressed: false)
        } else { super.deleteBackward() }
    }
    func textViewDidEndEditing(_ textView: UITextView) { if !closing { closing = true; onClose?() } }
    func dismissKeyboard(notify: Bool) {
        guard !closing else { return }
        closing = true; resignFirstResponder()
        if notify { onClose?() }
    }
    @objc private func closeKeyboard() { dismissKeyboard(notify: true) }
    @objc private func pressEscape() { GameInput.key("Escape", pressed: true); GameInput.key("Escape", pressed: false) }
    @objc private func pressTab() { GameInput.key("Tab", pressed: true); GameInput.key("Tab", pressed: false) }
    @objc private func pasteText() { if let value = UIPasteboard.general.string { _ = GameInput.text(String(value.prefix(16384))) } }
}
