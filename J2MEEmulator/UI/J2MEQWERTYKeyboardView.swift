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
        preservesSuperviewLayoutMargins = false
        insetsLayoutMarginsFromSafeArea = false
        layoutMargins = .zero
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
        guard let host = superview else { return }

        // Ép chặt 2 mép trái/phải sát 100% viền màn hình & neo cố định mép dưới
        for c in host.constraints where (c.firstItem as? UIView) === self || (c.secondItem as? UIView) === self {
            if c.firstAttribute == .leading || c.firstAttribute == .trailing || c.firstAttribute == .bottom {
                c.isActive = false
            }
        }
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        updateEmulatorScreenShift()
    }

    // MARK: - Đẩy UI game JAR lên cao khỏi khung nhập 40px

    private func updateEmulatorScreenShift() {
        guard let host = superview else { return }
        let isVisible = !isHidden && alpha > 0.01
        let totalKbHeight = heightConstraint?.constant ?? (gboardView.preferredKeyboardHeight + safeAreaInsets.bottom)

        let targetViews = host.subviews.filter { sub in
            if sub === self { return false }
            let className = NSStringFromClass(type(of: sub))
            return className.contains("EmulatorView")
                || className.contains("GLKView")
                || className.contains("MTKView")
                || className.contains("Display")
        }

        UIView.animate(withDuration: 0.20, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            for target in targetViews {
                if isVisible {
                    // Tính phần bị bàn phím + khung nhập 40px đè lên và đẩy cao thêm 20px thoáng mắt
                    let baseFrame = target.frame.applying(target.transform.inverted())
                    let keyboardTopY = host.bounds.height - totalKbHeight
                    let overlap = max(0, baseFrame.maxY - keyboardTopY)
                    let shiftY = overlap > 0 ? (overlap + 20.0) : (totalKbHeight * 0.55)
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
        textBuffer.append("\n")
        onTextChanged?(textBuffer)
        delegate?.qwertyKeyboardDidInsertText("\n")
        delegate?.qwertyKeyboardDidTapReturn()
    }

    func keyboardViewDidTapSubmit(_ keyboardView: JBKeyboardView) {
        onDone?()
        delegate?.qwertyKeyboardDidTapHide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            self.updateEmulatorScreenShift()
        }
    }

    func keyboardViewDidTapHide(_ keyboardView: JBKeyboardView) {
        delegate?.qwertyKeyboardDidTapHide()
        onCancel?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
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
