import UIKit

@objc protocol J2MEQWERTYKeyboardViewDelegate: AnyObject {
    func qwertyKeyboardDidInsertText(_ text: String)
    func qwertyKeyboardDidTapBackspace()
    func qwertyKeyboardDidTapReturn()
    func qwertyKeyboardDidTapHide()
}

final class J2MEQWERTYKeyboardView: UIView, JBKeyboardViewDelegate {
    weak var delegate: J2MEQWERTYKeyboardViewDelegate?

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

        // Tràn 2 mép màn hình 100% (leading = 0, trailing = 0)
        NSLayoutConstraint.activate([
            gboardView.topAnchor.constraint(equalTo: topAnchor),
            gboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gboardView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gboardView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor)
        ])

        let hc = heightAnchor.constraint(equalToConstant: gboardView.preferredKeyboardHeight + 20)
        hc.priority = .required
        hc.isActive = true
        self.heightConstraint = hc
    }

    override var isHidden: Bool {
        didSet {
            updateEmulatorScreenShift()
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        updateEmulatorScreenShift()
    }

    // MARK: - Đẩy UI màn hình JAR lên để không bị bàn phím che

    private func updateEmulatorScreenShift() {
        guard let host = superview else { return }
        let isVisible = !isHidden && alpha > 0.01
        let kbHeight = heightConstraint?.constant ?? (gboardView.preferredKeyboardHeight + safeAreaInsets.bottom)

        // Tìm các view render màn hình game JAR (EmulatorView / GLKView / MTKView)
        let targetViews = host.subviews.filter { sub in
            if sub === self { return false }
            let className = NSStringFromClass(type(of: sub))
            return className.contains("EmulatorView")
                || className.contains("GLKView")
                || className.contains("MTKView")
                || className.contains("Display")
        }

        UIView.animate(withDuration: 0.22, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            for target in targetViews {
                if isVisible {
                    // Tính phần màn hình game bị bàn phím đè lên và đẩy lên đúng khoảng đó
                    let overlap = max(0, target.frame.maxY - (host.bounds.height - kbHeight))
                    let shiftY = overlap > 0 ? min(overlap, kbHeight * 0.85) : (kbHeight * 0.42)
                    target.transform = CGAffineTransform(translationX: 0, y: -shiftY)
                } else {
                    target.transform = .identity
                }
            }
        }
    }

    // MARK: - API tương thích với GameViewController.swift

    @objc func begin(initialText: String = "") {
        textBuffer = initialText
        gboardView.currentText = initialText
        gboardView.reloadKeyboardLayout()
        onTextChanged?(textBuffer)
        updateEmulatorScreenShift()
    }

    @objc func setTheme(_ theme: Any?) {
        backgroundColor = UIColor(red: 0.106, green: 0.110, blue: 0.118, alpha: 1.0)
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
        // Phím xuống dòng (\n)
        textBuffer.append("\n")
        onTextChanged?(textBuffer)
        delegate?.qwertyKeyboardDidInsertText("\n")
        delegate?.qwertyKeyboardDidTapReturn()
    }

    func keyboardViewDidTapSubmit(_ keyboardView: JBKeyboardView) {
        // Nút gửi văn bản trên thanh công cụ
        onDone?()
        delegate?.qwertyKeyboardDidTapHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.updateEmulatorScreenShift()
        }
    }

    func keyboardViewDidTapHide(_ keyboardView: JBKeyboardView) {
        delegate?.qwertyKeyboardDidTapHide()
        onCancel?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.updateEmulatorScreenShift()
        }
    }

    func keyboardView(_ keyboardView: JBKeyboardView, didChangeHeight newHeight: CGFloat) {
        heightConstraint?.constant = newHeight + safeAreaInsets.bottom
        superview?.layoutIfNeeded()
        updateEmulatorScreenShift()
    }

    func keyboardView(_ keyboardView: JBKeyboardView, didToggleFloatingMode isFloating: Bool) {
        layer.cornerRadius = isFloating ? 16.0 : 0.0
        layer.masksToBounds = isFloating
    }
}
