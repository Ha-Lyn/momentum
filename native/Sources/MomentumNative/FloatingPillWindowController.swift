import AppKit

/// Floating status pill at the bottom of the screen. Borderless, ignores
/// mouse events and is only ordered front with `orderFrontRegardless`, so it
/// never becomes key and never activates Momentum (focus stays in the app
/// the user is typing in).
@MainActor
final class FloatingPillWindowController {
    private static let minimumWidth: CGFloat = 240
    private static let maximumWidth: CGFloat = 640
    private static let height: CGFloat = 70
    private static let horizontalPadding: CGFloat = 28

    private let window: NSWindow
    private let pillView = PillView(frame: NSRect(x: 0, y: 0, width: minimumWidth, height: height))

    /// Bumped on every state change. Pending fade-out completions and
    /// message timers only act if the generation is still theirs, so an
    /// earlier hide() can never hide a newly shown state.
    private var generation: UInt64 = 0
    private var messageTask: Task<Void, Never>?
    /// True while a note recording is in progress. Transient states
    /// (messages, hide()) fall back to the listening indicator instead of
    /// hiding the pill.
    private var isRecordingIndicatorActive = false

    init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.minimumWidth, height: Self.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = pillView
        window.alphaValue = 0
    }

    // MARK: Note recording

    func showRecordingIndicator() {
        isRecordingIndicatorActive = true
        showListening()
    }

    func hideRecordingIndicator() {
        isRecordingIndicatorActive = false
        hide()
    }

    // MARK: States

    func showListening() {
        present(.listening)
    }

    func showTranscribing() {
        present(.transcribing)
    }

    /// Shows `text` and hides the pill automatically after `duration`
    /// (or returns to the note recording indicator if one is active).
    func showMessage(_ text: String, duration: TimeInterval = 2.0) {
        present(.message(text))

        let messageGeneration = generation
        messageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self, self.generation == messageGeneration else {
                return
            }
            self.hide()
        }
    }

    func hide() {
        if isRecordingIndicatorActive {
            present(.listening)
            return
        }

        let hideGeneration = advanceGeneration()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                guard self.generation == hideGeneration else {
                    return
                }
                self.pillView.stopAnimating()
                self.window.orderOut(nil)
            }
        }
    }

    // MARK: Private

    @discardableResult
    private func advanceGeneration() -> UInt64 {
        generation &+= 1
        messageTask?.cancel()
        messageTask = nil
        return generation
    }

    private func present(_ content: PillView.Content) {
        advanceGeneration()

        pillView.configure(content)
        positionWindow(width: preferredWidth())
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }
    }

    private func preferredWidth() -> CGFloat {
        let contentWidth = pillView.contentFittingWidth() + Self.horizontalPadding * 2
        return min(max(Self.minimumWidth, ceil(contentWidth)), Self.maximumWidth)
    }

    private func positionWindow(width: CGFloat) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let frame = screen.visibleFrame
        let height = Self.height
        let x = frame.midX - (width / 2)
        let y = frame.minY + 40
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

private final class PillView: NSView {
    enum Content: Equatable {
        case listening
        case transcribing
        case message(String)
    }

    /// Longest text width before the label truncates.
    private static let maximumTextWidth: CGFloat = 540

    private let materialView = NSVisualEffectView()
    private let contentStack = NSStackView()
    private let indicatorView = NSView()
    private let spinner = NSProgressIndicator()
    private let textField = NSTextField(labelWithString: "Listening...")
    private let wavesStack = NSStackView()
    private var barViews: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(_ content: Content) {
        switch content {
        case .listening:
            textField.stringValue = "Listening..."
            indicatorView.isHidden = false
            wavesStack.isHidden = false
            setSpinnerVisible(false)
            startAnimating()
        case .transcribing:
            textField.stringValue = "Transcribing..."
            stopAnimating()
            indicatorView.isHidden = true
            wavesStack.isHidden = true
            setSpinnerVisible(true)
        case .message(let text):
            textField.stringValue = text
            stopAnimating()
            indicatorView.isHidden = true
            wavesStack.isHidden = true
            setSpinnerVisible(false)
        }
    }

    /// Width the content needs for the current state.
    func contentFittingWidth() -> CGFloat {
        layoutSubtreeIfNeeded()
        return contentStack.fittingSize.width
    }

    func startAnimating() {
        wantsLayer = true
        alphaValue = 1
        stopAnimating()

        for (index, bar) in barViews.enumerated() {
            let animation = CABasicAnimation(keyPath: "bounds.size.height")
            animation.fromValue = 6
            animation.toValue = 16
            animation.duration = 0.6
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.beginTime = CACurrentMediaTime() + (Double(index) * 0.12)
            bar.layer?.add(animation, forKey: "wave")
        }

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.12
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        indicatorView.layer?.add(pulse, forKey: "pulse")
    }

    func stopAnimating() {
        barViews.forEach { $0.layer?.removeAllAnimations() }
        indicatorView.layer?.removeAllAnimations()
        setSpinnerVisible(false)
    }

    private func setSpinnerVisible(_ visible: Bool) {
        spinner.isHidden = !visible
        if visible {
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
        }
    }

    private func setupUI() {
        wantsLayer = true

        materialView.material = .hudWindow
        materialView.blendingMode = .withinWindow
        materialView.state = .active
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 28
        materialView.layer?.borderWidth = 1
        materialView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        materialView.layer?.masksToBounds = true
        materialView.frame = bounds
        materialView.autoresizingMask = [.width, .height]
        addSubview(materialView)

        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(contentStack)

        indicatorView.wantsLayer = true
        indicatorView.translatesAutoresizingMaskIntoConstraints = false
        indicatorView.layer?.backgroundColor = NSColor.systemRed.cgColor
        indicatorView.layer?.cornerRadius = 5
        indicatorView.layer?.shadowColor = NSColor.systemRed.cgColor
        indicatorView.layer?.shadowOpacity = 0.8
        indicatorView.layer?.shadowRadius = 8
        indicatorView.layer?.shadowOffset = .zero
        NSLayoutConstraint.activate([
            indicatorView.widthAnchor.constraint(equalToConstant: 10),
            indicatorView.heightAnchor.constraint(equalToConstant: 10),
        ])

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.appearance = NSAppearance(named: .darkAqua)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isHidden = true
        NSLayoutConstraint.activate([
            spinner.widthAnchor.constraint(equalToConstant: 16),
            spinner.heightAnchor.constraint(equalToConstant: 16),
        ])

        textField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textField.textColor = NSColor(calibratedWhite: 0.94, alpha: 1)
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.cell?.usesSingleLineMode = true
        textField.cell?.truncatesLastVisibleLine = true
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.widthAnchor.constraint(lessThanOrEqualToConstant: Self.maximumTextWidth).isActive = true

        wavesStack.orientation = .horizontal
        wavesStack.alignment = .centerY
        wavesStack.spacing = 3

        for _ in 0..<4 {
            let bar = NSView()
            bar.wantsLayer = true
            bar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor
            bar.layer?.cornerRadius = 1.5
            bar.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: 3),
                bar.heightAnchor.constraint(equalToConstant: 12),
            ])
            barViews.append(bar)
            wavesStack.addArrangedSubview(bar)
        }

        contentStack.addArrangedSubview(indicatorView)
        contentStack.addArrangedSubview(spinner)
        contentStack.addArrangedSubview(textField)
        contentStack.addArrangedSubview(wavesStack)

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: materialView.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: materialView.centerYAnchor),
        ])
    }
}
