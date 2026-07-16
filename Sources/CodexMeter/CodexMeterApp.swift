import SwiftUI

@main
struct CodexMeterApp: App {
    @NSApplicationDelegateAdaptor(CodexMeterAppDelegate.self) private var appDelegate
    @StateObject private var store: AccountStore
    @StateObject private var dashboard: DashboardModel

    init() {
        _store = StateObject(wrappedValue: AccountStore())
        _dashboard = StateObject(wrappedValue: DashboardModel())
    }

    var body: some Scene {
        Window("大同", id: "dashboard") {
            MainView(store: store, dashboard: dashboard)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1180, height: 760)

        MenuBarExtra {
            MenuBarView(store: store, dashboard: dashboard)
        } label: {
            Label(menuBarTitle, systemImage: "chart.line.uptrend.xyaxis")
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarTitle: String {
        let snapshots = store.accounts.compactMap { dashboard.snapshots[$0.id] }
        guard !snapshots.isEmpty else { return "Codex" }
        return "\(Formatters.count(snapshots.totalCycleTokens)) T"
    }
}
