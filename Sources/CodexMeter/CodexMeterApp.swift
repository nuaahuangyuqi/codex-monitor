import Foundation
import SwiftUI

@main
struct CodexMeterApp: App {
    @NSApplicationDelegateAdaptor(CodexMeterAppDelegate.self) private var appDelegate
    @StateObject private var store: AccountStore
    @StateObject private var dashboard: DashboardModel
    @StateObject private var launchPresentation: LaunchPresentationModel
    @StateObject private var settings: AppSettings

    init() {
        // 保持旧版本的数据域，Bundle ID 更新后账号和刷新基线仍可无缝读取。
        let defaults = UserDefaults(suiteName: "com.codexmeter.macos") ?? .standard
        _store = StateObject(wrappedValue: AccountStore(defaults: defaults))
        _dashboard = StateObject(wrappedValue: DashboardModel(defaults: defaults))
        _launchPresentation = StateObject(wrappedValue: LaunchPresentationModel())
        _settings = StateObject(wrappedValue: AppSettings(defaults: defaults))
    }

    var body: some Scene {
        Window("Codex 账号仪表盘", id: "dashboard") {
            LaunchSequenceView(
                store: store,
                dashboard: dashboard,
                presentation: launchPresentation,
                settings: settings
            )
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
        .defaultSize(width: 1180, height: 760)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView(store: store, dashboard: dashboard)
                .preferredColorScheme(settings.appearance.colorScheme)
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
