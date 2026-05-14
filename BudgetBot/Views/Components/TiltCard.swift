import SwiftUI

/// Adds press-driven 3D tilt + shadow lift to any view. Used on analytics
/// cards so tapping them feels physical rather than flat. Compose by
/// applying the `.tiltOnPress()` modifier on a card content view.
struct TiltOnPressModifier: ViewModifier {
    @State private var pressed = false

    /// How far the card tilts forward when pressed, in degrees.
    var tiltDegrees: Double = 6
    /// How much the card scales when pressed.
    var scale: CGFloat = 0.985
    /// Tap callback fired on release.
    var onTap: () -> Void = {}

    func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? scale : 1)
            .rotation3DEffect(
                .degrees(pressed ? tiltDegrees : 0),
                axis: (x: 1, y: 0.6, z: 0),
                anchor: .center,
                anchorZ: 0,
                perspective: 0.5
            )
            .shadow(color: .black.opacity(pressed ? 0.08 : 0.16),
                    radius: pressed ? 4 : 10,
                    x: 0, y: pressed ? 2 : 6)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true } }
                    .onEnded { _ in
                        pressed = false
                        onTap()
                    }
            )
    }
}

extension View {
    /// Tilt the view forward in 3D while pressed and fire `onTap` on
    /// release. Don't combine with Button — this modifier handles taps
    /// itself.
    func tiltOnPress(degrees: Double = 6, scale: CGFloat = 0.985,
                     onTap: @escaping () -> Void = {}) -> some View {
        modifier(TiltOnPressModifier(tiltDegrees: degrees, scale: scale, onTap: onTap))
    }
}

/// Soft "breathing" pulse — useful on hero numbers to imply liveness.
/// Adds a subtle scale oscillation that returns to 1.0.
struct BreathingPulseModifier: ViewModifier {
    @State private var on = false
    var amplitude: CGFloat = 0.012
    var period: Double = 3.2

    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1 + amplitude : 1 - amplitude)
            .onAppear {
                withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

extension View {
    /// Apply to a hero metric so it feels alive without being distracting.
    func breathingPulse(amplitude: CGFloat = 0.012, period: Double = 3.2) -> some View {
        modifier(BreathingPulseModifier(amplitude: amplitude, period: period))
    }
}
