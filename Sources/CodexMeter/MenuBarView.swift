import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AccountStore
    @ObservedObject var dashboard: DashboardModel
    @State private var launchingAccountID: UUID?
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("大同").font(.headline)
                    Text(dashboard.days == 7 ? "当前 7 天额度周期" : "最近 30 天")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await dashboard.refresh(accounts: store.accounts) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(dashboard.isRefreshing || store.accounts.isEmpty)
            }

            if store.accounts.isEmpty {
                ContentUnavailableView("尚未添加账号", systemImage: "person.crop.circle.badge.plus")
                    .frame(height: 110)
            } else {
                HStack(spacing: 0) {
                    menuStat("周期 Token", Formatters.count(snapshots.totalCycleTokens))
                    Divider().frame(height: 34)
                    menuStat("历史", Formatters.count(snapshots.compactMap(\.lifetimeTokens).reduce(0, +)))
                    Divider().frame(height: 34)
                    menuStat("账号", "\(store.accounts.count)")
                }

                Divider()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.accounts) { account in
                            HStack(spacing: 9) {
                                Circle().fill(AppPalette.color(for: account.colorIndex)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(account.name).font(.callout.weight(.medium))
                                        Spacer()
                                        Text("剩余 \(Int(100 - quotaUsed(for: account)))%")
                                            .font(.caption).monospacedDigit()
                                    }
                                    ProgressView(value: quotaUsed(for: account), total: 100)
                                        .tint(quotaUsed(for: account) >= 85 ? .orange : AppPalette.color(for: account.colorIndex))
                                }
                                Button {
                                    openCodex(account)
                                } label: {
                                    if launchingAccountID == account.id {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.up.right.square")
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(launchingAccountID != nil)
                                .help("用此账号打开 Codex")
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Divider()
            HStack {
                Button("打开仪表盘") {
                    showDashboard()
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 350)
        .alert("无法打开 Codex", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("好") { launchError = nil }
        } message: {
            Text(launchError ?? "未知错误")
        }
    }

    private var snapshots: [AccountSnapshot] {
        store.accounts.compactMap { dashboard.snapshots[$0.id] }
    }

    private func quotaUsed(for account: AccountConfig) -> Double {
        dashboard.snapshots[account.id]?.quotaUsedPercent ?? 0
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

    private func showDashboard() {
        if let window = NSApp.windows.first(where: {
            $0.title == "大同" && ($0.isVisible || $0.isMiniaturized)
        }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "dashboard")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func menuStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}
