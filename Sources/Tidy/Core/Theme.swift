import SwiftUI

extension Color {
    init(hex: UInt32) {
        let r = Double((hex & 0xFF0000) >> 16) / 255
        let g = Double((hex & 0x00FF00) >> 8) / 255
        let b = Double(hex & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

/// A single, deliberate palette used everywhere in Tidy — a deep violet/teal
/// duo that reads as calm and premium rather than "system default blue",
/// with warm amber reserved strictly for things that need a second look.
enum Theme {
    static let violet = Color(hex: 0x8B5CF6)
    static let teal = Color(hex: 0x14B8A6)
    static let amber = Color(hex: 0xF59E0B)
    static let coral = Color(hex: 0xFB7185)

    static let accentGradient = LinearGradient(
        colors: [violet, teal],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static let warmGradient = LinearGradient(
        colors: [amber, coral],
        startPoint: .leading, endPoint: .trailing
    )

    static func safetyColor(_ safety: Safety) -> Color {
        switch safety {
        case .regenerable: return teal
        case .review: return amber
        case .personal: return violet
        }
    }

    /// Frosted, rounded card background used for every panel in the app.
    static func cardBackground(cornerRadius: CGFloat = 14) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

/// A pill-shaped, gradient-filled button used for the app's primary actions
/// ("Clean all safe items"). Everything else stays as native controls so the
/// app doesn't feel over-styled.
struct GradientButtonStyle: ButtonStyle {
    var gradient: LinearGradient = Theme.accentGradient
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(gradient)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: Theme.violet.opacity(0.25), radius: configuration.isPressed ? 2 : 6, y: 3)
    }
}

extension ButtonStyle where Self == GradientButtonStyle {
    static var gradientProminent: GradientButtonStyle { GradientButtonStyle() }
}
