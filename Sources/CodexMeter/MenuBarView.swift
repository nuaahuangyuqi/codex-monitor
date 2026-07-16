import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var store: AccountStore
    @ObservedObject var dashboard: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Monitor").font(.headline)
                    Text("最近 \(dashboard.days) 天")
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
                    menuStat("Token", Formatters.count(snapshots.totalTokens))
                    Divider().frame(height: 34)
                    menuStat("历史", Formatters.count(snapshots.compactMap(\.lifetimeTokens).reduce(0, +)))
                    Divider().frame(height: 34)
                    menuStat("账号", "\(store.accounts.count)")
                }

                Divider()

                ForEach(store.accounts.prefix(5)) { account in
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
                    }
                }
            }

            Divider()
            HStack {
                Button("打开仪表盘") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 350)
        .task {
            let newest = snapshots.compactMap(\.lastUpdated).max() ?? .distantPast
            if Date().timeIntervalSince(newest) > 5 * 60 {
                await dashboard.refresh(accounts: store.accounts)
            }
        }
    }

    private var snapshots: [AccountSnapshot] {
        store.accounts.compactMap { dashboard.snapshots[$0.id] }
    }

    private func quotaUsed(for account: AccountConfig) -> Double {
        dashboard.snapshots[account.id]?.quotaUsedPercent ?? 0
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
