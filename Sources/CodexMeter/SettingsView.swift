import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: appearanceKey) }
    }

    private let defaults: UserDefaults
    private let appearanceKey = "codexmeter.appearance.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.appearance = AppAppearance(
            rawValue: defaults.string(forKey: appearanceKey) ?? ""
        ) ?? .system
    }
}

struct SettingsView: View {
    @ObservedObject var store: AccountStore
    @ObservedObject var settings: AppSettings
    let onAddAccount: () -> Void
    let onReauthenticate: (AccountConfig) -> Void
    let onDelete: (AccountConfig) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("设置")
                        .font(.largeTitle.weight(.bold))
                    Text("管理账号与应用外观")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("外观", systemImage: "paintpalette.fill")
                        .font(.title3.weight(.semibold))
                    Picker("外观", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Label(appearance.title, systemImage: appearance.symbol)
                                .tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(18)
                .appGlassPanel(cornerRadius: 22, tint: .purple.opacity(0.06))

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("账号管理", systemImage: "person.2.fill")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Button("添加账号", systemImage: "plus") {
                            onAddAccount()
                        }
                        .appGlassButton(prominent: true)
                    }

                    if store.accounts.isEmpty {
                        ContentUnavailableView(
                            "尚未添加账号",
                            systemImage: "person.crop.circle.badge.plus",
                            description: Text("添加 ChatGPT 账号后即可查看 Codex 用量与额度。")
                        )
                        .frame(height: 180)
                        .appGlassPanel(cornerRadius: 20)
                    } else {
                        AppGlassContainer(spacing: 12) {
                            VStack(spacing: 12) {
                                ForEach(store.accounts) { account in
                                    HStack(spacing: 12) {
                                        Circle()
                                            .fill(AppPalette.color(for: account.colorIndex))
                                            .frame(width: 11, height: 11)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(account.name)
                                                .font(.headline)
                                            Text(account.email ?? account.plan.rawValue)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("重新授权", systemImage: "arrow.triangle.2.circlepath") {
                                            onReauthenticate(account)
                                        }
                                        .appGlassButton(tint: AppPalette.color(for: account.colorIndex).opacity(0.18))
                                        Button("删除", systemImage: "trash", role: .destructive) {
                                            onDelete(account)
                                        }
                                        .appGlassButton()
                                    }
                                    .padding(16)
                                    .appGlassPanel(
                                        cornerRadius: 18,
                                        tint: AppPalette.color(for: account.colorIndex).opacity(0.05),
                                        interactive: true
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
        .background { AppAmbientBackground() }
    }
}
