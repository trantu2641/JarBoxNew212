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
            if !isHidden {
                enforceFullWidthAndBottomAnchor()
            }
            updateEmulatorScreenShift(animated: true)
        }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        enforceFullWidthAndBottomAnchor()
        updateEmulatorScreenShift(animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Đảm bảo chiều ngang luôn bằng đúng chiều ngang màn hình (sát cả mép trái lẫn mép phải)
        if let host = superview, abs(bounds.width - host.bounds.width) > 0.5 {
            enforceFullWidthAndBottomAnchor()
        }
    }

    private func enforceFullWidthAndBottomAnchor() {
        guard let host = superview else { return }

        // Gỡ bỏ các constraint cũ từ GameViewController có thể khóa width/height/trailing của bàn phím
        for c in host.constraints where (c.firstItem as? UIView) === self || (c.secondItem as? UIView) === self {
            if c.firstAttribute == .leading || c.firstAttribute == .trailing || c.firstAttribute == .bottom || c.firstAttribute == .width || c.firstAttribute == .height {
                c.isActive = false
            }
        }
        for c in constraints where c !== heightConstraint {
            if c.firstAttribute == .width || c.firstAttribute == .height {
                c.isActive = false
            }
        }

        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: host.leadingAnchor),
            trailingAnchor.constraint(equalTo: host.trailingAnchor),
            widthAnchor.constraint(equalTo: host.widthAnchor),
            bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        let currentBottom = host.safeAreaInsets.bottom
        heightConstraint?.constant = gboardView.preferredKeyboardHeight + currentBottom
    }

    // MARK: - Đẩy UI game JAR đồng bộ theo mép trên bàn phím

    private func updateEmulatorScreenShift(animated: Bool) {
        guard let host = superview else { return }
        let isVisible = !isHidden && alpha > 0.01
        let totalKbHeight = heightConstraint?.constant ?? (gboardView.preferredKeyboardHeight + host.safeAreaInsets.bottom)

        let targetViews = host.subviews.filter { sub in
            if sub === self { return false }
            let className = NSStringFromClass(type(of: sub))
            return className.contains("EmulatorView")
                || className.contains("GLKView")
                || className.contains("MTKView")
                || className.contains("Display")
        }

        let applyShift = {
            for target in targetViews {
                if isVisible {
                    let baseFrame = target.frame.applying(target.transform.inverted())
                    let keyboardTopY = host.bounds.height - totalKbHeight
                    let overlap = max(0, baseFrame.maxY - keyboardTopY)
                    let shiftY = overlap > 0 ? (overlap + 16.0) : (totalKbHeight * 0.5)
                    target.transform = CGAffineTransform(translationX: 0, y: -shiftY)
                } else {
                    target.transform = .identity
                }
            }
        }

        if animated {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .beginFromCurrentState], animations: applyShift)
        } else {
            applyShift()
        }
    }

    // MARK: - API tương thích với GameViewController.swift

    @objc func begin(initialText: String = "") {
        textBuffer = initialText
        gboardView.currentText = initialText
        enforceFullWidthAndBottomAnchor()
        gboardView.reloadKeyboardLayout()
        onTextChanged?(textBuffer)
        updateEmulatorScreenShift(animated: true)
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
            self.updateEmulatorScreenShift(animated: true)
        }
    }

    func keyboardViewDidTapHide(_ keyboardView: JBKeyboardView) {
        delegate?.qwertyKeyboardDidTapHide()
        onCancel?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            self.updateEmulatorScreenShift(animated: true)
        }
    }

    func keyboardView(_ keyboardView: JBKeyboardView, didChangeHeight newHeight: CGFloat) {
        let bottomInset = superview?.safeAreaInsets.bottom ?? safeAreaInsets.bottom
        heightConstraint?.constant = newHeight + bottomInset
        setNeedsLayout()
        superview?.setNeedsLayout()
        superview?.layoutIfNeeded()
        updateEmulatorScreenShift(animated: false)
    }

    func keyboardView(_ keyboardView: JBKeyboardView, didToggleFloatingMode isFloating: Bool) {
        layer.cornerRadius = isFloating ? 16.0 : 0.0
        layer.masksToBounds = isFloating
    }
}
