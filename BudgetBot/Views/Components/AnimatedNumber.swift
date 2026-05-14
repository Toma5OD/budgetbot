import SwiftUI

/// Ticks a numeric value up from `0` to the target on appear.
///
/// Drives the "premium" feel on analytics tiles — instead of a static
/// €1,247 the user sees a flicker animate from €0 over half a second.
/// Cheap (single `withAnimation` on a Double) but high impact.
struct AnimatedDecimal: View {
    let target: Decimal
    let currency: String?
    var font: Font = .title.bold().monospacedDigit()
    var color: Color = .primary
    var duration: Double = 0.9

    @State private var displayed: Double = 0

    var body: some View {
        Text(formatted)
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: displayed))
            .onAppear {
                withAnimation(.smooth(duration: duration)) {
                    displayed = NSDecimalNumber(decimal: target).doubleValue
                }
            }
            .onChange(of: target) { _, new in
                withAnimation(.smooth(duration: duration)) {
                    displayed = NSDecimalNumber(decimal: new).doubleValue
                }
            }
    }

    private var formatted: String {
        let dec = Decimal(displayed)
        if let currency {
            return CurrencyFormatter.string(for: dec, currency: currency)
        }
        return String(format: "%.0f", displayed)
    }
}

/// Same idea for integer counters (regret count, transaction count, etc.)
struct AnimatedInt: View {
    let target: Int
    var font: Font = .title.bold().monospacedDigit()
    var color: Color = .primary
    var duration: Double = 0.8

    @State private var displayed: Int = 0

    var body: some View {
        Text("\(displayed)")
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText(value: Double(displayed)))
            .onAppear {
                withAnimation(.smooth(duration: duration)) { displayed = target }
            }
            .onChange(of: target) { _, new in
                withAnimation(.smooth(duration: duration)) { displayed = new }
            }
    }
}
