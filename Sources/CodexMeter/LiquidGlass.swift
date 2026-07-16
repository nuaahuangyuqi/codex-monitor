import SwiftUI

struct AppAmbientBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.12),
                        Color.clear,
                        Color.purple.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color.cyan.opacity(0.10))
                    .frame(width: proxy.size.width * 0.48)
                    .blur(radius: 90)
                    .position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.18)
                Circle()
                    .fill(Color.indigo.opacity(0.10))
                    .frame(width: proxy.size.width * 0.44)
                    .blur(radius: 100)
                    .position(x: proxy.size.width * 0.84, y: proxy.size.height * 0.78)
            }
        }
        .ignoresSafeArea()
    }
}

struct AppGlassContainer<Content: View>: View {
    let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

private struct AppGlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                Glass.regular
                    .tint(tint)
                    .interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.separator.opacity(0.32), lineWidth: 1)
                }
        }
    }
}

private struct AppGlassCapsuleModifier: ViewModifier {
    let tint: Color?
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                Glass.regular
                    .tint(tint)
                    .interactive(interactive),
                in: Capsule()
            )
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

private struct AppFrostedControlBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.regularMaterial)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.24), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
    }
}

extension View {
    func appGlassPanel(
        cornerRadius: CGFloat = 20,
        tint: Color? = nil,
        interactive: Bool = false
    ) -> some View {
        modifier(AppGlassPanelModifier(
            cornerRadius: cornerRadius,
            tint: tint,
            interactive: interactive
        ))
    }

    func appGlassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(AppGlassCapsuleModifier(tint: tint, interactive: interactive))
    }

    func appFrostedControlBar() -> some View {
        modifier(AppFrostedControlBarModifier())
    }

    @ViewBuilder
    func appGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else if let tint {
                buttonStyle(.glass(Glass.regular.tint(tint).interactive()))
            } else {
                buttonStyle(.glass)
            }
        } else if prominent {
            buttonStyle(.borderedProminent)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func appGlassMaterializeTransition() -> some View {
        if #available(macOS 26.0, *) {
            glassEffectTransition(.materialize)
        } else {
            self
        }
    }
}
