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
                            MenuAccountQuotaRow(
                                account: account,
                                snapshot: dashboard.snapshots[account.id],
                                isLaunching: launchingAccountID == account.id,
                                isLaunchDisabled: launchingAccountID != nil,
                                onOpenCodex: { openCodex(account) }
                            )
                        }
                    }
                }
                .frame(maxHeight: 420)
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
        .frame(width: 410)
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

private struct MenuAccountQuotaRow: View {
    let account: AccountConfig
    let snapshot: AccountSnapshot?
    let isLaunching: Bool
    let isLaunchDisabled: Bool
    let onOpenCodex: () -> Void

    private var usedPercent: Double {
        min(max(snapshot?.quotaUsedPercent ?? 0, 0), 100)
    }

    private var tint: Color {
        usedPercent >= 85 ? .orange : AppPalette.color(for: account.colorIndex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(AppPalette.color(for: account.colorIndex))
                    .frame(width: 8, height: 8)
                Text(account.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onOpenCodex) {
                    if isLaunching {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 74)
                    } else {
                        Text("打开 Codex")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLaunchDisabled)
                .help("用此账号打开 Codex")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snapshot?.quotaName ?? "Codex 周额度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("已用 \(Int(usedPercent))% · 剩余 \(Int(100 - usedPercent))%")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.secondary.opacity(0.18))
                        Capsule()
                            .fill(tint)
                            .frame(width: proxy.size.width * CGFloat(usedPercent / 100))
                    }
                }
                .frame(height: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot?.quotaName ?? "Codex 周额度")
                .accessibilityValue("已用 \(Int(usedPercent))%，剩余 \(Int(100 - usedPercent))%")

                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack {
                        if let resetDate = snapshot?.quotaResetDate {
                            Label("恢复：\(Formatters.countdown(to: resetDate, now: context.date))", systemImage: "clock")
                        } else {
                            Label("恢复时间暂无", systemImage: "clock")
                        }
                        Spacer()
                        Text("官方实时额度")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            if let errorMessage = snapshot?.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.separator.opacity(0.3), lineWidth: 1)
        }
    }
}
