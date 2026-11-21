import UIKit

@objc protocol J2MEQWERTYKeyboardViewDelegate: AnyObject {
    func qwertyKeyboardDidInsertText(_ text: String)
    func qwertyKeyboardDidTapBackspace()
    func qwertyKeyboardDidTapReturn()
    func qwertyKeyboardDidTapHide()
}

final class J2MEQWERTYKeyboardView: UIView, UITextViewDelegate {
    weak var delegate: J2MEQWERTYKeyboardViewDelegate?

    var onTextChanged: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    private let inputBar = UIView()
    private let textView = UITextView()
    private let sendButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private var previousText: String = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupNativeKeyboardBridge()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupNativeKeyboardBridge()
    }

    private func setupNativeKeyboardBridge() {
        backgroundColor = .clear
        isUserInteractionEnabled = false // Không chặn chạm vào màn hình game

        // Thanh nhập liệu 2 dòng gắn ngay phía trên bàn phím iPhone (inputAccessoryView)
        inputBar.frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 48)
        inputBar.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.96)

        textView.frame = CGRect(x: 8, y: 4, width: UIScreen.main.bounds.width - 96, height: 40)
        textView.backgroundColor = UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1.0)
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 15)
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        textView.returnKeyType = .default // Phím Return trên bàn phím iPhone xuống dòng thật
        textView.keyboardAppearance = .dark
        textView.delegate = self
        textView.inputAccessoryView = inputBar

        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        sendButton.frame = CGRect(x: UIScreen.main.bounds.width - 82, y: 7, width: 40, height: 34)
        sendButton.backgroundColor = UIColor(red: 0.66, green: 0.78, blue: 0.98, alpha: 1.0)
        sendButton.tintColor = UIColor(red: 0.02, green: 0.18, blue: 0.44, alpha: 1.0)
        sendButton.layer.cornerRadius = 17
        sendButton.setImage(UIImage(systemName: "paperplane.fill", withConfiguration: cfg), for: .normal)
        sendButton.addTarget(self, action: #selector(handleSendTap), for: .touchUpInside)

        closeButton.frame = CGRect(x: UIScreen.main.bounds.width - 38, y: 7, width: 32, height: 34)
        closeButton.tintColor = .lightGray
        closeButton.setImage(UIImage(systemName: "keyboard.chevron.compact.down", withConfiguration: cfg), for: .normal)
        closeButton.addTarget(self, action: #selector(handleCloseTap), for: .touchUpInside)

        inputBar.addSubview(textView)
        inputBar.addSubview(sendButton)
        inputBar.addSubview(closeButton)

        // Ẩn textView kích hoạt bàn phím ra ngoài khung nhìn nhưng vẫn là firstResponder
        textView.frame = CGRect(x: -1000, y: -1000, width: 10, height: 10)
        addSubview(textView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSystemKeyboardFrame(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    // Đặt lại textView vào thanh inputBar khi hiện bàn phím
    private let visibleTextView = UITextView()
    private var isSetupVisible = false

    private func ensureVisibleTextView() {
        guard !isSetupVisible else { return }
        isSetupVisible = true
        textView.removeFromSuperview()
        textView.frame = CGRect(x: 8, y: 4, width: UIScreen.main.bounds.width - 96, height: 40)
        textView.autoresizingMask = [.flexibleWidth]
        sendButton.autoresizingMask = [.flexibleLeftMargin]
        closeButton.autoresizingMask = [.flexibleLeftMargin]
        inputBar.addSubview(textView)
    }

    @objc func begin(initialText: String = "") {
        ensureVisibleTextView()
        isHidden = false
        previousText = initialText
        textView.text = initialText
        onTextChanged?(initialText)
        DispatchQueue.main.async {
            self.textView.becomeFirstResponder()
        }
    }

    @objc func setTheme(_ theme: Any?) {
        textView.keyboardAppearance = .dark
    }

    // MARK: - Tự động đẩy UI game JAR lên theo bàn phím iPhone

    @objc private func handleSystemKeyboardFrame(_ note: Notification) {
        guard let host = superview,
              let endFrame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }

        let converted = host.convert(endFrame, from: nil)
        let isShowing = converted.minY < host.bounds.height - 10
        let kbHeight = max(0, host.bounds.height - converted.minY)

        let targetViews = host.subviews.filter { sub in
            if sub === self { return false }
            let name = NSStringFromClass(type(of: sub))
            return name.contains("EmulatorView") || name.contains("GLKView") || name.contains("MTKView") || name.contains("Display")
        }

        UIView.animate(withDuration: 0.25) {
            for target in targetViews {
                if isShowing {
                    let baseFrame = target.frame.applying(target.transform.inverted())
                    let overlap = max(0, baseFrame.maxY - converted.minY)
                    let shift = overlap > 0 ? (overlap + 12) : (kbHeight * 0.45)
                    target.transform = CGAffineTransform(translationX: 0, y: -shift)
                } else {
                    target.transform = .identity
                }
            }
        }
    }

    // MARK: - UITextViewDelegate (Đồng bộ gõ Telex/VNI chuẩn iOS vào game JAR)

    func textViewDidChange(_ textView: UITextView) {
        let current = textView.text ?? ""
        onTextChanged?(current)

        // Tính phần chênh lệch khi gõ dấu Tiếng Việt (Telex thay thế chữ cũ bằng chữ có dấu)
        let commonPrefix = current.commonPrefix(with: previousText)
        let deleteCount = previousText.count - commonPrefix.count
        let insertedPart = String(current.dropFirst(commonPrefix.count))

        if deleteCount > 0 {
            for _ in 0..<deleteCount {
                delegate?.qwertyKeyboardDidTapBackspace()
            }
        }
        if !insertedPart.isEmpty {
            if insertedPart == "\n" {
                delegate?.qwertyKeyboardDidInsertText("\n")
                delegate?.qwertyKeyboardDidTapReturn()
            } else {
                delegate?.qwertyKeyboardDidInsertText(insertedPart)
            }
        }
        previousText = current
    }

    @objc private func handleSendTap() {
        textView.resignFirstResponder()
        isHidden = true
        onDone?()
        delegate?.qwertyKeyboardDidTapHide()
    }

    @objc private func handleCloseTap() {
        textView.resignFirstResponder()
        isHidden = true
        onCancel?()
        delegate?.qwertyKeyboardDidTapHide()
    }
}
