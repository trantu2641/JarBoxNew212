//
// J2MEQWERTYKeyboardView.swift
// JarBox Gboard-style keyboard adapter.
//

import UIKit

final class J2MEQWERTYKeyboardView: UIView {
    var onTextChanged: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    private var text = "" {
        didSet { onTextChanged?(text) }
    }

    private var attached = false
    private let manager = JBKeyboardManager()
    private var theme = UserDefaults.standard.string(forKey: "J2MEQWERTYTheme") ?? "dark"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        isHidden = true
        installManagerCallbacks()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard !attached, superview != nil else { return }
        attached = true

        manager.hostViewController = nearestViewController()
        manager.attach(to: self)
        manager.setKeyboardHeight(clampedKeyboardHeight(), animated: false)
        manager.hide()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard attached else { return }
        manager.setKeyboardHeight(clampedKeyboardHeight(), animated: false)
    }

    func begin(initialText: String = "") {
        text = initialText
        manager.keyboardView.vietnamese = true
        manager.keyboardView.shift = false
        manager.keyboardView.ime.language = "vi"
        manager.keyboardView.ime.telexEnabled = true
        manager.setKeyboardHeight(clampedKeyboardHeight(), animated: false)
        isHidden = false
        manager.show()
    }

    func clear() {
        text = ""
    }

    func setTheme(_ value: String) {
        theme = value
        UserDefaults.standard.set(value, forKey: "J2MEQWERTYTheme")
        manager.keyboardView.reloadKeyboard()
    }

    // Internal dismiss only. Do not call onCancel here because
    // GameViewController.finishQWERTYInput() is already the owner of the
    // confirm/cancel callback and would otherwise recurse.
    func dismissKeyboard() {
        manager.hide()
        isHidden = true
    }

    private func clampedKeyboardHeight() -> CGFloat {
        max(180, min(420, bounds.height > 0 ? bounds.height : 285))
    }

    private func installManagerCallbacks() {
        manager.currentTextProvider = { [weak self] in
            self?.text ?? ""
        }

        manager.insertTextHandler = { [weak self] (value: String) in
            guard let self else { return }
            self.text.append(contentsOf: value)
        }

        manager.deleteBackwardHandler = { [weak self] in
            guard let self, !self.text.isEmpty else { return }
            self.text.removeLast()
        }

        manager.returnHandler = { [weak self] in
            guard let self else { return }
            self.manager.hide()
            self.isHidden = true
            self.onDone?()
        }
    }

    private func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}
