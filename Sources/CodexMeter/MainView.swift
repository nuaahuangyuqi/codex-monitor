import SwiftUI

private enum SidebarSelection: Hashable {
    case all
    case account(UUID)
    case settings
}

struct MainView: View {
    @ObservedObject var store: AccountStore
    @ObservedObject var dashboard: DashboardModel
    @ObservedObject var settings: AppSettings

    @State private var selection: SidebarSelection? = .all
    @State private var showingLogin = false
    @State private var loginAccount: AccountConfig?
    @State private var accountToDelete: AccountConfig?
    @State private var launchingAccountID: UUID?
    @State private var launchError: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            if activeSelection != .settings {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        Picker("时间范围", selection: $dashboard.days) {
                            Text("7 天").tag(7)
                            Text("30 天").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 126)

                        Button {
                            Task { await dashboard.refresh(accounts: visibleAccounts) }
                        } label: {
                            if dashboard.isRefreshing {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("刷新", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(dashboard.isRefreshing || store.accounts.isEmpty)
                        .appGlassButton()

                        Button {
                            loginAccount = nil
                            showingLogin = true
                        } label: {
                            Label("添加账号", systemImage: "plus")
                        }
                        .appGlassButton()
                    }
                    .padding(6)
                    .appFrostedControlBar()
                    .fixedSize()
                }
            }
        }
        .sheet(isPresented: $showingLogin) {
            AccountLoginView(store: store, account: loginAccount) {
                // 新增或重新授权后不自动发起网络刷新，由用户点击刷新。
            }
        }
        .alert("无法打开 Codex", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("好") { launchError = nil }
        } message: {
            Text(launchError ?? "未知错误")
        }
        .confirmationDialog(
            "删除账号？",
            isPresented: Binding(
                get: { accountToDelete != nil },
                set: { if !$0 { accountToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: accountToDelete
        ) { account in
            Button("删除“\(account.name)”", role: .destructive) {
                store.delete(account)
                dashboard.remove(accountID: account.id)
                if activeSelection != .settings { selection = .all }
            }
        } message: { _ in
            Text("该账号在本机保存的 Codex 登录凭据和监控记录也会被删除。")
        }
        .task {
            await dashboard.refreshInitial30Days(accounts: store.accounts)
        }
    }

    private var sidebar: some View {
        ZStack {
            AppAmbientBackground()
            VStack(spacing: 0) {
                ScrollView {
                    AppGlassContainer(spacing: 10) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("概览")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            sidebarRow(
                                title: "全部账号",
                                subtitle: nil,
                                systemImage: "square.grid.2x2",
                                target: .all,
                                tint: .blue
                            )

                            Text("账号")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, 4)

                            ForEach(store.accounts) { account in
                                Button {
                                    selection = .account(account.id)
                                } label: {
                                    HStack(spacing: 9) {
                                        Circle()
                                            .fill(AppPalette.color(for: account.colorIndex))
                                            .frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(account.name)
                                                .foregroundStyle(.primary)
                                            Text(dashboard.snapshots[account.id]?.planType?.capitalized ?? account.plan.rawValue)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if dashboard.snapshots[account.id]?.errorMessage != nil {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 9)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                }
                                .buttonStyle(.plain)
                                .appGlassPanel(
                                    cornerRadius: 14,
                                    tint: activeSelection == .account(account.id)
                                        ? AppPalette.color(for: account.colorIndex).opacity(0.22)
                                        : nil,
                                    interactive: true
                                )
                                .contextMenu {
                                    Button("重新授权") {
                                        loginAccount = account
                                        showingLogin = true
                                    }
                                    Button("删除", role: .destructive) { accountToDelete = account }
                                }
                            }
                        }
                    }
                    .padding(12)
                }

                Divider()

                sidebarRow(
                    title: "设置",
                    subtitle: "账号与外观",
                    systemImage: "gearshape.fill",
                    target: .settings,
                    tint: .purple
                )
                .padding(12)
            }
        }
        .navigationTitle("账号管理")
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private var detail: some View {
        if activeSelection == .settings {
            SettingsView(
                store: store,
                settings: settings,
                onAddAccount: {
                    loginAccount = nil
                    showingLogin = true
                },
                onReauthenticate: reauthenticate,
                onDelete: { accountToDelete = $0 }
            )
        } else if store.accounts.isEmpty {
            ZStack {
                AppAmbientBackground()
                ContentUnavailableView {
                    Label("开始监控 Codex", systemImage: "chart.line.uptrend.xyaxis")
                } description: {
                    Text("登录 ChatGPT 账号，查看 Codex Token 活动、方案与额度恢复时间。")
                } actions: {
                    Button("添加第一个账号") {
                        loginAccount = nil
                        showingLogin = true
                    }
                    .appGlassButton(prominent: true)
                }
            }
        } else {
            DashboardView(
                accounts: visibleAccounts,
                snapshots: visibleAccounts.compactMap { dashboard.snapshots[$0.id] },
                days: dashboard.days,
                launchingAccountID: launchingAccountID,
                onOpenCodex: openCodex,
                onReauthenticate: reauthenticate
            )
        }
    }

    private var visibleAccounts: [AccountConfig] {
        switch activeSelection {
        case .all: return store.accounts
        case .account(let id): return store.accounts.filter { $0.id == id }
        case .settings: return store.accounts
        }
    }

    private var activeSelection: SidebarSelection {
        selection ?? .all
    }

    private func sidebarRow(
        title: String,
        subtitle: String?,
        systemImage: String,
        target: SidebarSelection,
        tint: Color
    ) -> some View {
        Button {
            selection = target
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .appGlassPanel(
            cornerRadius: 14,
            tint: activeSelection == target ? tint.opacity(0.22) : nil,
            interactive: true
        )
    }

    private func openCodex(_ account: AccountConfig) {
        guard launchingAccountID == nil else { return }
        launchingAccountID = account.id
        Task {
            do {
                try await CodexDesktopLauncher.open(
                    accountID: account.id,
                    allAccountIDs: store.accounts.map(\.id)
                )
            } catch {
                launchError = error.localizedDescription
            }
            launchingAccountID = nil
        }
    }

    private func reauthenticate(_ account: AccountConfig) {
        loginAccount = account
        showingLogin = true
    }
}
