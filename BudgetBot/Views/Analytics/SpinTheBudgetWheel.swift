import SwiftUI

/// "Spin the Budget Wheel" — a deliberately fun, slightly mean roulette
/// of the user's top spending categories. Tap → wheel spins (eases over
/// ~2.7s) → lands on a random category → a roast appears below.
///
/// Visual: a multi-segment pie drawn in `Canvas` (so each wedge gets its
/// own palette colour), a fixed pointer at the top, and a counter that
/// remembers how many times you've spun.
struct SpinTheBudgetWheel: View {

    /// One wedge on the wheel. Constructed from the analytics
    /// `byCategory` aggregation but kept thin so this view is reusable.
    struct Wedge: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let amount: Decimal      // expense magnitude in base currency
        let color: Color
    }

    let wedges: [Wedge]
    let currency: String
    /// Used in roast lines that quote the figure ("€312 of pure regret").
    let theme: Theme

    @State private var rotation: Angle = .zero
    @State private var spinning = false
    @State private var spinsCompleted = 0
    @State private var landedIndex: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spin the Budget Wheel").font(.headline)
                Spacer()
                Text("\(spinsCompleted)× spun")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            if wedges.isEmpty {
                Text("Not enough categories yet — capture more receipts and the wheel fills out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                wheelStack
                    .frame(height: 280)

                Button {
                    spin()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "dial.high.fill")
                            .rotationEffect(spinning ? .degrees(360) : .zero)
                            .animation(.linear(duration: 0.8).repeatCount(spinning ? 5 : 0, autoreverses: false),
                                       value: spinning)
                        Text(spinning ? "Spinning…" : (spinsCompleted == 0 ? "Spin" : "Spin again"))
                            .font(.callout.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [theme.tint, theme.tint.opacity(0.6)],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                }
                .disabled(spinning)
                .buttonStyle(.plain)

                if let idx = landedIndex, idx < wedges.count {
                    roastCard(wedges[idx])
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
        }
        .padding(16)
        .themedCard()
    }

    // MARK: - Wheel rendering

    private var wheelStack: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2 - 8

            ZStack {
                // Wedges
                Canvas { ctx, _ in
                    let center = CGPoint(x: size / 2, y: size / 2)
                    let total = wedges.reduce(Decimal(0)) { $0 + $1.amount }
                    let totalDouble = max(0.01, NSDecimalNumber(decimal: total).doubleValue)
                    var startAngle: Double = -.pi / 2     // start at top

                    for w in wedges {
                        let frac = NSDecimalNumber(decimal: w.amount).doubleValue / totalDouble
                        let sweep = frac * 2 * .pi
                        let endAngle = startAngle + sweep

                        var path = Path()
                        path.move(to: center)
                        path.addArc(center: center,
                                    radius: radius,
                                    startAngle: .radians(startAngle),
                                    endAngle: .radians(endAngle),
                                    clockwise: false)
                        path.closeSubpath()

                        ctx.fill(path, with: .color(w.color))
                        ctx.stroke(path, with: .color(Color.black.opacity(0.18)), lineWidth: 0.6)

                        // Label on the wedge, only if the wedge is fat enough.
                        if sweep > 0.30 {
                            let mid = startAngle + sweep / 2
                            let textRadius = radius * 0.6
                            let pt = CGPoint(
                                x: center.x + cos(mid) * textRadius,
                                y: center.y + sin(mid) * textRadius
                            )
                            let txt = Text(w.label)
                                .font(.caption.bold())
                                .foregroundColor(.white)
                            ctx.draw(txt, at: pt, anchor: .center)
                        }

                        startAngle = endAngle
                    }
                }
                .frame(width: size, height: size)
                .rotationEffect(rotation)
                .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
                .animation(.easeOut(duration: 2.7), value: rotation)

                // Center hub
                Circle()
                    .fill(theme.background.viewBackgroundColor)
                    .frame(width: size * 0.18, height: size * 0.18)
                    .overlay(
                        Circle().stroke(theme.tint.opacity(0.55), lineWidth: 1.5)
                    )

                // Pointer at top, fixed.
                Triangle()
                    .fill(
                        LinearGradient(colors: [theme.tint, theme.tint.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 22, height: 28)
                    .offset(y: -(size / 2 - 4))
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Roast

    private func roastCard(_ w: Wedge) -> some View {
        let amt = CurrencyFormatter.string(for: w.amount, currency: currency)
        let roast = Self.roastLine(for: w.label, amount: amt)
        return HStack(spacing: 12) {
            Circle().fill(w.color)
                .frame(width: 14, height: 14)
                .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(w.label)
                    .font(.subheadline.bold())
                Text(roast)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(amt)
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    // MARK: - Spin logic

    private func spin() {
        guard !wedges.isEmpty else { return }
        spinning = true

        // Pick a random target wedge weighted by share of total spend.
        let total = wedges.reduce(Decimal(0)) { $0 + $1.amount }
        let totalDouble = max(0.01, NSDecimalNumber(decimal: total).doubleValue)
        let weights = wedges.map { NSDecimalNumber(decimal: $0.amount).doubleValue / totalDouble }
        let target = Self.weightedRandom(weights: weights)

        // Compute the angle of the target wedge's centre.
        var cumulative: Double = 0
        for (i, w) in weights.enumerated() {
            if i == target { break }
            cumulative += w
        }
        let wedgeMidFraction = cumulative + (weights[target] / 2)
        let wedgeMidDegrees = wedgeMidFraction * 360

        // Pointer is at top (which in screen-coords is -90°). The wheel
        // starts drawn from -90° too, so the wedge under the pointer is
        // the one whose mid-angle equals -current-rotation modulo 360.
        // To land the *target* wedge at the pointer we need:
        //   rotation = (-wedgeMidDegrees) mod 360 + 360 * full_spins
        // Plus a tiny ±jitter so it doesn't land dead-centre every time.
        let jitter = Double.random(in: -8...8)
        let baseRotation = -wedgeMidDegrees + jitter
        let fullSpins = Double(Int.random(in: 5...7) * 360)
        let newRotation = rotation.degrees + fullSpins + (baseRotation - rotation.degrees.truncatingRemainder(dividingBy: 360))

        withAnimation(.easeOut(duration: 2.7)) {
            rotation = .degrees(newRotation)
        }
        landedIndex = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.75) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                landedIndex = target
                spinsCompleted += 1
                spinning = false
            }
        }
    }

    private static func weightedRandom(weights: [Double]) -> Int {
        let total = weights.reduce(0, +)
        guard total > 0 else { return 0 }
        let pick = Double.random(in: 0..<total)
        var acc: Double = 0
        for (i, w) in weights.enumerated() {
            acc += w
            if pick < acc { return i }
        }
        return weights.count - 1
    }

    // MARK: - Roast lines

    /// Tiny canned roast library keyed by category name. Falls back to a
    /// generic line if the category isn't in the table.
    static func roastLine(for category: String, amount: String) -> String {
        let key = category.lowercased()
        let line = roasts[key] ?? generic
        return line.replacingOccurrences(of: "{amount}", with: amount)
    }

    private static let generic = "{amount} on this. Brave choice."
    private static let roasts: [String: String] = [
        "coffee":             "{amount} on coffee. The bean is winning.",
        "dining":             "Restaurants pocketed {amount}. The hob exists.",
        "alcohol":            "{amount} liquidated, literally.",
        "groceries":          "{amount} on groceries — at least you ate.",
        "shopping":           "{amount} on shopping. Closet says hello.",
        "clothing":           "{amount} on clothes. Tags still on?",
        "electronics":        "{amount} on gadgets. The drawer thanks you.",
        "streaming":          "{amount} on streaming. Pick a show, finish a show.",
        "other subscriptions": "{amount} on subs you forgot you had.",
        "mobile plan":        "{amount} on the phone bill. The price of being reachable.",
        "internet":           "{amount} on internet. Worth it. Probably.",
        "rent":               "{amount} on rent. Capitalism: 1, You: 0.",
        "fuel":               "{amount} at the pump. The tank is bottomless.",
        "taxi & ride-share":  "{amount} on cabs. The bus exists.",
        "entertainment":      "{amount} on a good time. Receipts unclear.",
        "travel":             "{amount} on travel. Worth every cent. We mean it.",
        "personal care":      "{amount} on looking good. It's working.",
        "books & media":      "{amount} on books. Still on chapter 2.",
        "hobbies":            "{amount} on the hobby. The hobby costs more than the joy.",
        "gifts given":        "{amount} on gifts. Generous king/queen.",
        "pharmacy":           "{amount} at the pharmacy. Worth it for not dying.",
        "medical":            "{amount} on health. Future you says thanks.",
        "cash withdrawal":    "{amount} into the wallet. Where did it actually go?",
        "bank fees":          "{amount} to the bank. For… holding your money."
    ]
}

// MARK: - Helpers

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

private extension Theme.BackgroundStyle {
    /// A solid colour that approximates the theme background, used to
    /// fill the wheel hub so it visually punches through.
    var viewBackgroundColor: Color {
        switch self {
        case .solid(let c): return c
        case .linearGradient(let cs, _, _):
            return cs.first ?? Color(UIColor.systemBackground)
        }
    }
}
