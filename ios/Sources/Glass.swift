import SwiftUI

/// iOS 17-compatible glass surface. The official iOS 26 Liquid Glass APIs
/// require the iOS 26 SDK, so this uses system materials, gradient rims and
/// depth shadows to get the same visual language on the current build SDK.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.025, green: 0.055, blue: 0.10),
                        Color(red: 0.035, green: 0.10, blue: 0.14),
                        Color(red: 0.02, green: 0.045, blue: 0.075)
                    ]
                    : [
                        Color(red: 0.96, green: 0.99, blue: 0.98),
                        Color(red: 0.92, green: 0.97, blue: 1.0),
                        Color(red: 0.87, green: 0.94, blue: 1.0)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.green.opacity(colorScheme == .dark ? 0.18 : 0.22),
                    Color.green.opacity(0)
                ],
                center: UnitPoint(x: 0.08, y: 0.06),
                startRadius: 10,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color.cyan.opacity(colorScheme == .dark ? 0.14 : 0.18),
                    Color.cyan.opacity(0)
                ],
                center: UnitPoint(x: 0.92, y: 0.90),
                startRadius: 10,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}

struct GlassCardModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                colorScheme == .dark
                    ? Color(red: 0.055, green: 0.10, blue: 0.16).opacity(0.86)
                    : Color.white.opacity(0.72),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(colorScheme == .dark ? 0.32 : 0.86),
                                .white.opacity(colorScheme == .dark ? 0.06 : 0.16)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.22 : 0.07),
                radius: 12,
                x: 0,
                y: 6
            )
    }
}

extension View {
    func glassCard(padding: CGFloat = 16,
                   cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(padding: padding, cornerRadius: cornerRadius))
    }
}

struct GlassProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.68, blue: 0.46),
                        Color(red: 0.04, green: 0.53, blue: 0.42)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .green.opacity(0.25), radius: 16, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}
