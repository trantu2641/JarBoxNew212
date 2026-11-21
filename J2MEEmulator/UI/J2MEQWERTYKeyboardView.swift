import UIKit

@objc protocol J2MEQWERTYKeyboardViewDelegate: AnyObject {
    func qwertyKeyboardDidInsertText(_ text: String)
    func qwertyKeyboardDidTapBackspace()
    func qwertyKeyboardDidTapReturn()
    func qwertyKeyboardDidTapHide()
}

final class J2MEQWERTYKeyboardView: UIView, JBKeyboardViewDelegate {
    weak var delegate: J2MEQWERTYKeyboardViewDelegate?

    // Các callback tương thích trực tiếp với GameViewController.swift
    var onTextChanged: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    private let gboardView = JBKeyboardView(frame: .zero)
    private var heightConstraint: NSLayoutConstraint?
    private var textBuffer: String = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = UIColor(red: 0.106, green: 0.110, blue: 0.118, alpha: 1.0)
        gboardView.delegate = self
        gboardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gboardView)

        NSLayoutConstraint.activate([
            gboardView.topAnchor.constraint(equalTo: topAnchor),
            gboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gboardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gboardView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])

        let hc = heightAnchor.constraint(equalToConstant: gboardView.preferredKeyboardHeight + 24)
        hc.priority = .defaultHigh
        hc.isActive = true
        self.heightConstraint = hc
    }

    // MARK: - API tương thích với GameViewController.swift

    @objc func begin(initialText: String = "") {
        textBuffer = initialText
        gboardView.reloadKeyboardLayout()
        onTextChanged?(textBuffer)
    }

    @objc func setTheme(_ theme: Any?) {
        let name = (theme as? String)?.lowercased() ?? ""
        if name.contains("light") || name.contains("white") {
            backgroundColor = UIColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1.0)
        } else if name.contains("amoled") || name.contains("black") {
            backgroundColor = .black
        } else {
            // Mặc định Gboard Material You Dark (#1B1C1E)
            backgroundColor = UIColor(red: 0.106, green: 0.110, blue: 0.118, alpha: 1.0)
        }
        gboardView.reloadKeyboardLayout()
    }

    // MARK: - JBKeyboardViewDelegate

    func keyboardView(_ keyboardView: JBKeyboardView, didInsertText text: String) {
        textBuffer.append(text)
        onTextChanged?(textBuffer)
        delegate?.qwertyKeyboardDidInsertText(text)
    }

    func keyboardViewDidTapBackspace(_ keyboardView: JBKeyboardView) {
        if !textBuffer.isEmpty {
            textBuffer.removeLast()
        }
        onTextChanged?(textBuffer)
        delegate?.qwertyKeyboardDidTapBackspace()
    }

    func keyboardViewDidTapReturn(_ keyboardView: JBKeyboardView) {
        delegate?.qwertyKeyboardDidTapReturn()
        onDone?()
    }

    func keyboardViewDidTapHide(_ keyboardView: JBKeyboardView) {
        delegate?.qwertyKeyboardDidTapHide()
        onCancel?()
    }

    func keyboardView(_ keyboardView: JBKeyboardView, didChangeHeight newHeight: CGFloat) {
        heightConstraint?.constant = newHeight + safeAreaInsets.bottom
        superview?.layoutIfNeeded()
    }

    func keyboardView(_ keyboardView: JBKeyboardView, didToggleFloatingMode isFloating: Bool) {
        layer.cornerRadius = isFloating ? 18.0 : 0.0
        layer.masksToBounds = isFloating
    }
}
