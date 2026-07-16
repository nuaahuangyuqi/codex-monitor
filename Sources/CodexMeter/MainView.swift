import SwiftUI

private enum SidebarSelection: Hashable {
    case all
    case account(UUID)
}

struct MainView: View {
    @ObservedObject var store: AccountStore
    @ObservedObject var dashboard: DashboardModel

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
            ToolbarItemGroup {
                Picker("时间范围", selection: $dashboard.days) {
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                }
                .frame(width: 110)

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

                Button {
                    loginAccount = nil
                    showingLogin = true
                } label: {
                    Label("添加账号", systemImage: "plus")
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
                selection = .all
            }
        } message: { _ in
            Text("该账号在本机保存的 Codex 登录凭据和监控记录也会被删除。")
        }
        .task {
            await dashboard.refreshInitial30Days(accounts: store.accounts)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("概览") {
                    Label("全部账号", systemImage: "square.grid.2x2")
                        .tag(SidebarSelection.all)
                }
                Section("账号") {
                    ForEach(store.accounts) { account in
                        HStack(spacing: 9) {
                            Circle()
                                .fill(AppPalette.color(for: account.colorIndex))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
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
                        .tag(SidebarSelection.account(account.id))
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

            Divider()
            HStack {
                Text("OpenAI 官方登录")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .navigationTitle("账号管理")
        .frame(minWidth: 220)
    }

    @ViewBuilder
    private var detail: some View {
        if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("开始监控 Codex", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("登录 ChatGPT 账号，查看 Codex Token 活动、方案与额度恢复时间。")
            } actions: {
                Button("添加第一个账号") {
                    loginAccount = nil
                    showingLogin = true
                }
                .buttonStyle(.borderedProminent)
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
        switch selection ?? .all {
        case .all: return store.accounts
        case .account(let id): return store.accounts.filter { $0.id == id }
        }
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
