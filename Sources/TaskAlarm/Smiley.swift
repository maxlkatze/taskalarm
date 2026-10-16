import AppKit
import SwiftUI

/// The smiley's mood. It's always on your side: it only looks worried when
/// something was actually missed — everything else is encouragement.
enum Mood: Equatable {
    case celebrating   // you just finished something
    case excited       // it's time! let's go
    case eager         // things to do today: "you've got this"
    case happy         // all clear, relaxed
    case worried       // something was missed

    var face: FaceParams {
        switch self {
        case .celebrating: return FaceParams(curve: 1.0, open: 0.65, brow: 0, eye: 0.7)
        case .excited:     return FaceParams(curve: 1.0, open: 0.5, brow: 0, eye: 1.15)
        case .eager:       return FaceParams(curve: 0.95, open: 0.28, brow: 0, eye: 1.05)
        case .happy:       return FaceParams(curve: 0.8, open: 0.0, brow: 0, eye: 1.0)
        case .worried:     return FaceParams(curve: -0.75, open: 0.45, brow: 1.0, eye: 1.25)
        }
    }

    var hasBlush: Bool { self != .worried }
}

/// Animatable parameters of a face. Everything is in unit space.
struct FaceParams: VectorArithmetic {
    var curve: Double   // -1 frown … 1 big smile
    var open: Double    // 0 closed … 1 wide open
    var brow: Double    // 0 none … 1 very worried
    var eye: Double     // eye height multiplier (0.1 = blink)

    static var zero: FaceParams { FaceParams(curve: 0, open: 0, brow: 0, eye: 0) }

    static func + (l: FaceParams, r: FaceParams) -> FaceParams {
        FaceParams(curve: l.curve + r.curve, open: l.open + r.open, brow: l.brow + r.brow, eye: l.eye + r.eye)
    }
    static func - (l: FaceParams, r: FaceParams) -> FaceParams {
        FaceParams(curve: l.curve - r.curve, open: l.open - r.open, brow: l.brow - r.brow, eye: l.eye - r.eye)
    }
    mutating func scale(by rhs: Double) {
        curve *= rhs; open *= rhs; brow *= rhs; eye *= rhs
    }
    var magnitudeSquared: Double { curve * curve + open * open + brow * brow + eye * eye }

    func blinking(_ amount: Double) -> FaceParams {
        var p = self
        p.eye *= (1 - 0.9 * amount)
        return p
    }
}

/// Shared geometry so the menu bar icon, the app icon and SwiftUI faces look identical.
enum FaceGeometry {
    /// Filled parts: eyes and the inside of an open mouth.
    static func fills(in r: CGRect, _ p: FaceParams) -> Path {
        var path = Path()
        let eyeW = 0.115 * r.width
        let eyeH = max(0.018, 0.17 * p.eye) * r.height
        for x in [0.355, 0.645] {
            let c = point(r, x, 0.41)
            path.addEllipse(in: CGRect(x: c.x - eyeW / 2, y: c.y - eyeH / 2, width: eyeW, height: eyeH))
        }
        path.addPath(mouth(in: r, p))
        return path
    }

    /// Stroked parts: the mouth outline and the eyebrows.
    static func strokes(in r: CGRect, _ p: FaceParams, includeBrows: Bool = true) -> Path {
        var path = mouth(in: r, p)
        if includeBrows, p.brow > 0.05 {
            let lift = p.brow * 0.075
            let reach = 0.10 + 0.06 * min(1, p.brow)
            path.move(to: point(r, 0.27, 0.27))
            path.addLine(to: point(r, 0.27 + reach, 0.27 - lift))
            path.move(to: point(r, 0.73, 0.27))
            path.addLine(to: point(r, 0.73 - reach, 0.27 - lift))
        }
        return path
    }

    static func mouth(in r: CGRect, _ p: FaceParams) -> Path {
        let base = 0.645 - p.curve * 0.07
        let depth = p.curve * 0.22
        var path = Path()
        path.move(to: point(r, 0.29, base))
        path.addQuadCurve(to: point(r, 0.71, base), control: point(r, 0.5, base + depth))
        // Return along a flatter curve: the area between both curves is the open mouth.
        let upper = depth * (1 - p.open) - (p.curve < 0 ? -p.open * 0.06 : p.open * 0.03)
        path.addQuadCurve(to: point(r, 0.29, base), control: point(r, 0.5, base + upper))
        path.closeSubpath()
        return path
    }

    static func point(_ r: CGRect, _ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height)
    }
}

/// A shape that draws either the filled or the stroked parts of the face, and animates between moods.
struct FacePart: Shape {
    enum Kind { case fills, strokes }
    var params: FaceParams
    var kind: Kind

    var animatableData: FaceParams {
        get { params }
        set { params = newValue }
    }

    func path(in rect: CGRect) -> Path {
        kind == .fills ? FaceGeometry.fills(in: rect, params) : FaceGeometry.strokes(in: rect, params)
    }
}

/// The animated smiley used throughout the UI.
struct SmileyView: View {
    var mood: Mood
    var size: CGFloat
    var color: Color = Theme.accent

    @State private var blink = false
    @State private var pop = 0
    @State private var wiggle = 0

    var body: some View {
        let face = mood.face.blinking(blink ? 1 : 0)
        ZStack {
            Circle()
                .fill(color.gradient)
            // Soft highlight for a little depth.
            Circle()
                .fill(
                    RadialGradient(colors: [.white.opacity(0.45), .clear],
                                   center: UnitPoint(x: 0.32, y: 0.25),
                                   startRadius: 0, endRadius: size * 0.55)
                )
            HStack(spacing: size * 0.36) {
                Ellipse().fill(Theme.blush.opacity(0.75))
                    .frame(width: size * 0.16, height: size * 0.09)
                Ellipse().fill(Theme.blush.opacity(0.75))
                    .frame(width: size * 0.16, height: size * 0.09)
            }
            .offset(y: size * 0.1)
            .opacity(mood.hasBlush ? 1 : 0)
            .scaleEffect(mood.hasBlush ? 1 : 0.4)

            FacePart(params: face, kind: .fills)
                .fill(Theme.ink)
            FacePart(params: face, kind: .strokes)
                .stroke(Theme.ink, style: StrokeStyle(lineWidth: max(1.2, size * 0.07), lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.45, dampingFraction: 0.55), value: mood)
        .animation(.easeInOut(duration: 0.07), value: blink)
        .keyframeAnimator(initialValue: 1.0, trigger: pop) { view, scale in
            view.scaleEffect(scale)
        } keyframes: { _ in
            SpringKeyframe(1.18, duration: 0.18, spring: .snappy)
            SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
        }
        .keyframeAnimator(initialValue: 0.0, trigger: wiggle) { view, angle in
            view.rotationEffect(.degrees(angle))
        } keyframes: { _ in
            CubicKeyframe(-10, duration: 0.07)
            CubicKeyframe(9, duration: 0.09)
            CubicKeyframe(-6, duration: 0.09)
            CubicKeyframe(3, duration: 0.08)
            CubicKeyframe(0, duration: 0.08)
        }
        .onChange(of: mood) { _, new in
            pop += 1
            if new == .worried { wiggle += 1 }
        }
        .task(id: mood) {
            // Natural blinking, plus a nervous wiggle every few seconds when worried.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.2...5.0)))
                if Task.isCancelled { break }
                blink = true
                try? await Task.sleep(for: .milliseconds(130))
                blink = false
                if mood == .worried { wiggle += 1 }
            }
        }
        .accessibilityLabel("Smiley, mood \(String(describing: mood))")
    }
}
