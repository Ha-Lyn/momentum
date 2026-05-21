import AppKit

@MainActor
final class FloatingPillWindowController {
    private let window: NSWindow
    private let pillView = PillView(frame: NSRect(x: 0, y: 0, width: 240, height: 70))

    init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 70),
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

    func showRecordingIndicator() {
        positionWindow()
        pillView.startAnimating()
        window.orderFrontRegardless()

        window.animator().alphaValue = 1
    }

    func hideRecordingIndicator() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            window.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                self.pillView.stopAnimating()
                self.window.orderOut(nil)
            }
        }
    }

    private func positionWindow() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let frame = screen.visibleFrame
        let width: CGFloat = 240
        let height: CGFloat = 70
        let x = frame.midX - (width / 2)
        let y = frame.minY + 40
        window.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

private final class PillView: NSView {
    private let materialView = NSVisualEffectView()
    private let indicatorView = NSView()
    private let textField = NSTextField(labelWithString: "Listening...")
    private var barViews: [NSView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func startAnimating() {
        wantsLayer = true
        alphaValue = 1

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

        let contentStack = NSStackView()
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

        textField.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textField.textColor = NSColor(calibratedWhite: 0.94, alpha: 1)

        let wavesStack = NSStackView()
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
        contentStack.addArrangedSubview(textField)
        contentStack.addArrangedSubview(wavesStack)

        NSLayoutConstraint.activate([
            contentStack.centerXAnchor.constraint(equalTo: materialView.centerXAnchor),
            contentStack.centerYAnchor.constraint(equalTo: materialView.centerYAnchor),
        ])
    }
}
