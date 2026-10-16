import AppKit

/// The menu bar smiley. Its color shows the status, its face shows the mood,
/// and it blinks, bounces and shakes with tiny frame-based animations.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    var onLeftClick: (() -> Void)?
    var onRightClick: ((NSStatusBarButton) -> Void)?

    var button: NSStatusBarButton? { item.button }

    // Animated state
    private var face = Mood.happy.face
    private var targetFace = Mood.happy.face
    private var color = Theme.goodNS
    private var targetColor = Theme.goodNS
    private var blink = 0.0
    private var bounceStart: Date?
    private var shakeStart: Date?
    private var blinkStart: Date?
    private var badge = 0

    private var frameTimer: Timer?
    private var blinkTimer: Timer?

    override init() {
        super.init()
        if let b = item.button {
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.imagePosition = .imageLeft
            b.toolTip = "TaskAlarm"
        }
        render()
        scheduleBlink()
    }

    func apply(mood: Mood, status: StatusLevel, badge: Int) {
        var changed = false
        if mood.face != targetFace { targetFace = mood.face; changed = true }
        if status.nsColor != targetColor { targetColor = status.nsColor; changed = true }
        if badge != self.badge {
            self.badge = badge
            updateTitle()
        }
        if changed { startAnimating() }
    }

    /// Happy hop when a task gets done.
    func bounce() {
        bounceStart = Date()
        startAnimating()
    }

    /// Nervous shake when something is missed.
    func shake() {
        shakeStart = Date()
        startAnimating()
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            onRightClick?(sender)
        } else {
            onLeftClick?()
        }
    }

    // MARK: - Animation loop

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        let t = Timer(timeInterval: Double.random(in: 3...7), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.blinkStart = Date()
                self?.startAnimating()
                self?.scheduleBlink()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        blinkTimer = t
    }

    private func startAnimating() {
        guard frameTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
        RunLoop.main.add(t, forMode: .common)
        frameTimer = t
    }

    private func step() {
        let now = Date()
        var busy = false

        // Ease face and color toward targets.
        let diff = targetFace - face
        if diff.magnitudeSquared > 0.00005 {
            var d = diff
            d.scale(by: 0.18)
            face = face + d
            busy = true
        } else {
            face = targetFace
        }
        if let mixed = color.blended(withFraction: 0.2, of: targetColor), !color.isClose(to: targetColor) {
            color = mixed
            busy = true
        } else {
            color = targetColor
        }

        if let s = blinkStart {
            let t = now.timeIntervalSince(s) / 0.16
            if t >= 1 { blink = 0; blinkStart = nil } else { blink = sin(t * .pi); busy = true }
        }
        if let s = bounceStart, now.timeIntervalSince(s) > 0.9 { bounceStart = nil }
        if let s = shakeStart, now.timeIntervalSince(s) > 0.6 { shakeStart = nil }
        if bounceStart != nil || shakeStart != nil { busy = true }

        render()
        if !busy {
            frameTimer?.invalidate()
            frameTimer = nil
        }
    }

    private func render() {
        let now = Date()
        var dx = 0.0, dy = 0.0, scale = 1.0
        if let s = bounceStart {
            let t = now.timeIntervalSince(s)
            dy = -abs(sin(t * 11)) * 3.0 * exp(-t * 3.5)
            scale = 1 + 0.08 * sin(t * 11) * exp(-t * 4)
        }
        if let s = shakeStart {
            let t = now.timeIntervalSince(s)
            dx = sin(t * 55) * 1.8 * exp(-t * 4.5)
        }

        let params = face.blinking(blink)
        let fill = color
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let d = 15.0 * scale
            let faceRect = CGRect(x: rect.midX - d / 2 + dx, y: rect.midY - d / 2 + dy, width: d, height: d)

            ctx.setFillColor(fill.cgColor)
            ctx.fillEllipse(in: faceRect)

            // Punch the features out so they take the menu bar's own color.
            ctx.setBlendMode(.destinationOut)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(FaceGeometry.fills(in: faceRect, params).cgPath)
            ctx.fillPath()
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(FaceGeometry.strokes(in: faceRect, params, includeBrows: params.brow > 0.4).cgPath)
            ctx.strokePath()
            return true
        }
        image.isTemplate = false
        item.button?.image = image
    }

    private func updateTitle() {
        guard let b = item.button else { return }
        if badge > 0 {
            b.attributedTitle = NSAttributedString(string: " \(badge)", attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .baselineOffset: 0.5,
            ])
        } else {
            b.title = ""
        }
    }
}

private extension NSColor {
    func isClose(to other: NSColor) -> Bool {
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return true }
        return abs(a.redComponent - b.redComponent) < 0.01
            && abs(a.greenComponent - b.greenComponent) < 0.01
            && abs(a.blueComponent - b.blueComponent) < 0.01
    }
}
