import SwiftUI
import UIKit

extension View {
    /// Puts the classic keyboard bar above the software keyboard: previous/next on the left, Done on the right,
    /// with space between Done and the keys.
    func keyboardDoneToolbar() -> some View {
        background {
            KeyboardAccessoryInstaller()
        }
    }

    /// Lets a downward drag on a scroll view dismiss the keyboard interactively.
    func interactiveKeyboardDismiss() -> some View {
        scrollDismissesKeyboard(.interactively)
    }
}

func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct KeyboardAccessoryInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardAccessoryAnchor {
        KeyboardAccessoryCenter.shared.start()
        return KeyboardAccessoryAnchor()
    }

    func updateUIView(_ uiView: KeyboardAccessoryAnchor, context: Context) {
        uiView.scheduleInstall()
    }
}

/// Invisible anchor used to find the screen's text fields before they are focused.
private final class KeyboardAccessoryAnchor: UIView {
    private var installScheduled = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleInstall()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleInstall()
    }

    func scheduleInstall() {
        guard !installScheduled else { return }
        installScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.installScheduled = false
            guard let root = self?.enclosingControllerView() else { return }
            KeyboardAccessoryCenter.shared.install(in: root)
        }
    }

    private func enclosingControllerView() -> UIView? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller.view
            }
            responder = current.next
        }
        return window
    }
}

private final class KeyboardAccessoryCenter {
    static let shared = KeyboardAccessoryCenter()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(editingBegan(_:)),
            name: UITextField.textDidBeginEditingNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(editingBegan(_:)),
            name: UITextView.textDidBeginEditingNotification,
            object: nil
        )
    }

    func install(in root: UIView) {
        for input in KeyboardFieldSearch.inputs(in: root) {
            attach(to: input)
        }
    }

    @objc private func editingBegan(_ notification: Notification) {
        guard let input = notification.object as? UIView else { return }
        let alreadyAttached = KeyboardFieldSearch.accessory(of: input) != nil
        attach(to: input)
        if !alreadyAttached {
            (input as? UITextField)?.reloadInputViews()
            (input as? UITextView)?.reloadInputViews()
        }
        KeyboardFieldSearch.accessory(of: input)?.refreshNavigation()
    }

    private func attach(to input: UIView) {
        guard KeyboardFieldSearch.accessory(of: input) == nil else { return }
        let accessory = CahootsKeyboardAccessory()
        if let field = input as? UITextField {
            field.inputAccessoryView = accessory
        } else if let textView = input as? UITextView {
            textView.inputAccessoryView = accessory
        }
    }
}

private enum KeyboardFieldSearch {
    static func accessory(of input: UIView) -> CahootsKeyboardAccessory? {
        if let field = input as? UITextField {
            return field.inputAccessoryView as? CahootsKeyboardAccessory
        }
        if let textView = input as? UITextView {
            return textView.inputAccessoryView as? CahootsKeyboardAccessory
        }
        return nil
    }

    static func inputs(in root: UIView) -> [UIView] {
        var found: [UIView] = []
        func walk(_ view: UIView) {
            guard !view.isHidden, view.alpha > 0.01 else { return }
            if let field = view as? UITextField, field.isEnabled, field.isUserInteractionEnabled {
                found.append(field)
            } else if let textView = view as? UITextView, textView.isEditable, textView.isUserInteractionEnabled {
                found.append(textView)
            }
            for child in view.subviews {
                walk(child)
            }
        }
        walk(root)
        return found.sorted { lhs, rhs in
            let left = lhs.convert(lhs.bounds, to: nil)
            let right = rhs.convert(rhs.bounds, to: nil)
            if abs(left.minY - right.minY) > 12 { return left.minY < right.minY }
            return left.minX < right.minX
        }
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    static func controllerView(containing view: UIView) -> UIView? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller.view
            }
            responder = current.next
        }
        return view.window
    }
}

/// Full-width bar that sits on the keyboard. Buttons are held above the keys so Done is not flush with them.
private final class CahootsKeyboardAccessory: UIInputView {
    /// Standard accessory row, plus room under the controls before the keys start.
    private static let barHeight: CGFloat = 44
    private static let keyboardGap: CGFloat = 10
    private static var totalHeight: CGFloat { barHeight + keyboardGap }

    private let toolbar = UIToolbar()
    private let previousItem: UIBarButtonItem
    private let nextItem: UIBarButtonItem
    private let doneItem: UIBarButtonItem
    private var showsArrows = false

    init() {
        let symbol = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        previousItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.up", withConfiguration: symbol),
            style: .plain,
            target: nil,
            action: nil
        )
        nextItem = UIBarButtonItem(
            image: UIImage(systemName: "chevron.down", withConfiguration: symbol),
            style: .plain,
            target: nil,
            action: nil
        )
        doneItem = UIBarButtonItem(title: "Done", style: .plain, target: nil, action: nil)
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.totalHeight), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        autoresizingMask = [.flexibleWidth]
        previousItem.target = self
        previousItem.action = #selector(previousField)
        previousItem.accessibilityLabel = "Previous field"
        nextItem.target = self
        nextItem.action = #selector(nextField)
        nextItem.accessibilityLabel = "Next field"
        doneItem.target = self
        doneItem.action = #selector(finishEditing)
        configureChrome()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: Self.totalHeight)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width, height: Self.totalHeight)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshNavigation()
    }

    func refreshNavigation() {
        guard let field = owningInput(), let scope = KeyboardFieldSearch.controllerView(containing: field) else {
            applyItems(showsArrows: false, canGoPrevious: false, canGoNext: false)
            return
        }
        let fields = KeyboardFieldSearch.inputs(in: scope)
        guard let index = fields.firstIndex(where: { $0 === field }) else {
            applyItems(showsArrows: fields.count > 1, canGoPrevious: false, canGoNext: false)
            return
        }
        applyItems(
            showsArrows: fields.count > 1,
            canGoPrevious: index > 0,
            canGoNext: index < fields.count - 1
        )
    }

    private func configureChrome() {
        let hairline = UIView()
        hairline.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.14)
                : UIColor.black.withAlphaComponent(0.12)
        }
        hairline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hairline)

        let appearance = UIToolbarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        toolbar.standardAppearance = appearance
        toolbar.compactAppearance = appearance
        toolbar.scrollEdgeAppearance = appearance
        let buttonColor: UIColor = if #available(iOS 26.0, *) {
            // Bar buttons use the label color. systemBlue plus a done/prominent style fills the capsule.
            .label
        } else {
            .systemBlue
        }
        toolbar.tintColor = buttonColor
        doneItem.tintColor = buttonColor
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: topAnchor),
            hairline.leadingAnchor.constraint(equalTo: leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            toolbar.topAnchor.constraint(equalTo: topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.keyboardGap),
        ])
        applyItems(showsArrows: false, canGoPrevious: false, canGoNext: false)
    }

    private func applyItems(showsArrows: Bool, canGoPrevious: Bool, canGoNext: Bool) {
        previousItem.isEnabled = canGoPrevious
        nextItem.isEnabled = canGoNext
        guard showsArrows != self.showsArrows || toolbar.items == nil else { return }
        self.showsArrows = showsArrows
        let gap = UIBarButtonItem(systemItem: .fixedSpace)
        gap.width = 8
        let flex = UIBarButtonItem(systemItem: .flexibleSpace)
        toolbar.items = showsArrows
            ? [previousItem, gap, nextItem, flex, doneItem]
            : [flex, doneItem]
    }

    @objc private func previousField() {
        shiftFocus(by: -1)
    }

    @objc private func nextField() {
        shiftFocus(by: 1)
    }

    @objc private func finishEditing() {
        dismissKeyboard()
    }

    private func shiftFocus(by offset: Int) {
        guard let field = owningInput(), let scope = KeyboardFieldSearch.controllerView(containing: field) else { return }
        let fields = KeyboardFieldSearch.inputs(in: scope)
        guard let index = fields.firstIndex(where: { $0 === field }) else { return }
        let nextIndex = index + offset
        guard fields.indices.contains(nextIndex) else { return }
        fields[nextIndex].becomeFirstResponder()
    }

    private func owningInput() -> UIView? {
        guard let window = KeyboardFieldSearch.keyWindow() else { return nil }
        return KeyboardFieldSearch.inputs(in: window).first { KeyboardFieldSearch.accessory(of: $0) === self }
    }
}

/// Reports how far the keyboard (including its accessory bar) overlaps the window.
struct KeyboardHeightReader: UIViewRepresentable {
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> KeyboardHeightAnchor {
        let view = KeyboardHeightAnchor()
        view.onHeight = { [binding = $height] newHeight in
            guard abs(binding.wrappedValue - newHeight) > 0.5 else { return }
            binding.wrappedValue = newHeight
        }
        return view
    }

    func updateUIView(_ uiView: KeyboardHeightAnchor, context: Context) {
        uiView.onHeight = { [binding = $height] newHeight in
            guard abs(binding.wrappedValue - newHeight) > 0.5 else { return }
            binding.wrappedValue = newHeight
        }
    }
}

final class KeyboardHeightAnchor: UIView {
    var onHeight: (CGFloat) -> Void = { _ in }
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.apply(note)
            })
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            onHeight(0)
            return
        }
    }

    private func apply(_ notification: Notification) {
        guard let window else { return }
        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero
        let converted = window.convert(frame, from: nil)
        onHeight(max(0, window.bounds.maxY - converted.minY))
    }
}
