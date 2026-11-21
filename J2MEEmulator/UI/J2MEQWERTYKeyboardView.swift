//
// J2MEQWERTYKeyboardView.swift
// Custom in-app QWERTY keyboard. It never invokes the iOS system keyboard.
// Supports English QWERTY and Vietnamese Unicode input with direct vowel/tone keys.
//
import UIKit

final class J2MEQWERTYKeyboardView: UIView {
    var onTextChanged: ((String) -> Void)?
    var onDone: (() -> Void)?
    var onCancel: (() -> Void)?

    private(set) var text = "" {
        didSet { onTextChanged?(text) }
    }
    private var shift = false
    private var vietnamese = false
    private var keyButtons: [UIButton] = []
    private var theme = UserDefaults.standard.string(forKey: "J2MEQWERTYTheme") ?? "dark"

    private let englishRows = [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","s","d","f","g","h","j","k","l"],
        ["⇧","z","x","c","v","b","n","m","⌫"],
        ["VI","space","↵"]
    ]
    private let vietnameseRows = [
        ["q","w","e","r","t","y","u","i","o","p"],
        ["a","ă","â","s","d","đ","f","g","h","j","k","l"],
        ["z","x","c","v","b","n","m","ê","ô","ơ","ư","⌫"],
        ["EN","´","`","̉","˜","̣","^","space","↵"]
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        applyTheme()
        layer.cornerRadius = 12
        clipsToBounds = true
        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func begin(initialText: String = "") {
        text = initialText
        rebuild()
    }

    func clear() { text = ""; rebuild() }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        keyButtons.removeAll()

        let rows = vietnamese ? vietnameseRows : englishRows
        let outer = UIStackView()
        outer.axis = .vertical
        outer.spacing = 5
        outer.distribution = .fillEqually
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7)
        ])

        for row in rows {
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.spacing = 4
            stack.distribution = .fillEqually
            for key in row {
                let b = makeButton(key)
                stack.addArrangedSubview(b)
                keyButtons.append(b)
            }
            outer.addArrangedSubview(stack)
        }
    }

    private func makeButton(_ key: String) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(key == "space" ? "Space" : key, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: key.count > 1 ? 12 : 18, weight: .medium)
        b.backgroundColor = keyBackgroundColor()
        b.layer.cornerRadius = 7
        b.addAction(UIAction { [weak self] _ in self?.press(key) }, for: .touchUpInside)
        return b
    }

    func setTheme(_ value: String) {
        theme = value
        UserDefaults.standard.set(value, forKey: "J2MEQWERTYTheme")
        applyTheme()
        rebuild()
    }

    private func applyTheme() {
        switch theme {
        case "light": backgroundColor = UIColor(white: 0.92, alpha: 1)
        case "blue": backgroundColor = UIColor(red: 0.05, green: 0.11, blue: 0.22, alpha: 0.97)
        default: backgroundColor = UIColor.black.withAlphaComponent(0.92)
        }
    }

    private func keyBackgroundColor() -> UIColor {
        switch theme {
        case "light": return UIColor.white
        case "blue": return UIColor(red: 0.10, green: 0.20, blue: 0.38, alpha: 1)
        default: return UIColor(white: 0.18, alpha: 1)
        }
    }

    private func press(_ key: String) {
        switch key {
        case "⇧":
            shift.toggle(); rebuild()
        case "⌫":
            if !text.isEmpty { text.removeLast(); onTextChanged?(text) }
        case "space":
            text.append(" ")
        case "↵":
            onDone?()
        case "VI":
            vietnamese = true; shift = false; rebuild()
        case "EN":
            vietnamese = false; shift = false; rebuild()
        case "´": applyTone("́")
        case "`": applyTone("̀")
        case "̉": applyTone("̉")
        case "˜": applyTone("̃")
        case "̣": applyTone("̣")
        case "^": applyVowelModifier()
        default:
            let value = shift ? key.uppercased() : key
            text.append(value)
            if shift { shift = false; rebuild() }
        }
        onTextChanged?(text)
    }

    private func applyTone(_ combiningMark: String) {
        guard !text.isEmpty else { return }
        var chars = Array(text)
        guard let index = lastVowelIndex(chars) else { return }
        let composed = (String(chars[index]) + combiningMark).precomposedStringWithCanonicalMapping
        chars[index] = composed.first ?? chars[index]
        text = String(chars)
    }

    private func applyVowelModifier() {
        guard !text.isEmpty else { return }
        var chars = Array(text)
        let i = chars.count - 1
        switch chars[i] {
        case "a": chars[i] = "â"; case "e": chars[i] = "ê"; case "o": chars[i] = "ô"
        case "A": chars[i] = "Â"; case "E": chars[i] = "Ê"; case "O": chars[i] = "Ô"
        default: break
        }
        text = String(chars)
    }

    private func lastVowelIndex(_ chars: [Character]) -> Int? {
        let vowels = Set("aeiouyăâêôơưAEIOUYĂÂÊÔƠƯ")
        for i in stride(from: chars.count - 1, through: 0, by: -1) {
            if vowels.contains(chars[i]) { return i }
            if chars[i] == " " { break }
        }
        return nil
    }
}
