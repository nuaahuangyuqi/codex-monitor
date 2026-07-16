import SwiftUI

@MainActor
final class LaunchPresentationModel: ObservableObject {
    @Published var hasPlayed = false
}

struct LaunchSequenceView: View {
    @ObservedObject var store: AccountStore
    @ObservedObject var dashboard: DashboardModel
    @ObservedObject var presentation: LaunchPresentationModel
    @ObservedObject var settings: AppSettings

    @State private var hasStarted = false
    @State private var showTitle = false
    @State private var showDashboard = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            AppAmbientBackground()

            if showDashboard || presentation.hasPlayed {
                MainView(store: store, dashboard: dashboard, settings: settings)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }

            if showSplash && !presentation.hasPlayed {
                Text("天下大同")
                    .font(.custom("Kaiti SC", size: 64).weight(.medium))
                    .tracking(18)
                    .padding(.leading, 18)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.35), radius: 18)
                    .opacity(showTitle ? 1 : 0)
                    .scaleEffect(showTitle ? 1 : 0.96)
                    .blur(radius: showTitle ? 0 : 8)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            guard !presentation.hasPlayed else {
                showSplash = false
                showDashboard = true
                return
            }

            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.75)) {
                showTitle = true
            }

            try? await Task.sleep(nanoseconds: 1_150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.85)) {
                showTitle = false
                showDashboard = true
            }

            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }
            showSplash = false
            presentation.hasPlayed = true
        }
    }
}
