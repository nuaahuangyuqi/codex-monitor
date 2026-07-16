import Charts
import SwiftUI

struct DashboardView: View {
    let accounts: [AccountConfig]
    let snapshots: [AccountSnapshot]
    let days: Int
    let launchingAccountID: UUID?
    let onOpenCodex: (AccountConfig) -> Void
    let onReauthenticate: (AccountConfig) -> Void

    @State private var selectedDate: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                summary
                availabilityNote
                accountOverview
                chartCard
            }
            .padding(24)
        }
        .background { AppAmbientBackground() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(accounts.count == 1 ? accounts[0].name : "全部账号")
                    .font(.largeTitle.weight(.bold))
                Text(days == 7
                     ? "当前 7 天额度恢复周期 · \(accounts.count) 个账号"
                     : "最近 30 天 · \(accounts.count) 个账号")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if snapshots.contains(where: { $0.errorMessage != nil }) {
                Label("部分数据不可用", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var summary: some View {
        AppGlassContainer(spacing: 14) {
            HStack(spacing: 14) {
                MetricCard(title: "刷新周期 Token", value: Formatters.count(snapshots.totalCycleTokens), icon: "text.word.spacing", tint: .blue)
                MetricCard(title: "历史 Token", value: Formatters.count(snapshots.compactMap(\.lifetimeTokens).reduce(0, +)), icon: "clock.arrow.circlepath", tint: .purple)
                MetricCard(title: "单日峰值", value: Formatters.count(snapshots.compactMap(\.peakDailyTokens).max() ?? 0), icon: "chart.line.uptrend.xyaxis", tint: .teal)
                MetricCard(title: "账号", value: "\(accounts.count)", icon: "person.2.fill", tint: .orange)
            }
        }
    }

    private var availabilityNote: some View {
        Label("刷新周期 Token 是上次刷新到本次刷新之间的新增量；7/30 天只改变本地图表范围。API 调用次数与美元费用不在网页登录返回范围内。", systemImage: "info.circle.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appGlassPanel(cornerRadius: 14, tint: .blue.opacity(0.10))
    }

    private var accountOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("账号概览")
                .font(.title3.weight(.semibold))
            AppGlassContainer(spacing: 14) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), spacing: 14)], spacing: 14) {
                    ForEach(accounts) { account in
                        AccountStatusCard(
                            account: account,
                            snapshot: snapshot(for: account.id),
                            isLaunching: launchingAccountID == account.id,
                            onOpenCodex: { onOpenCodex(account) },
                            onReauthenticate: { onReauthenticate(account) }
                        )
                    }
                }
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日使用量")
                        .font(.headline)
                    Text(selectedValueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                Spacer()
                Text("Token")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .appGlassCapsule(tint: .blue.opacity(0.08))
            }

            if series.isEmpty {
                ContentUnavailableView("暂无 Token 活动", systemImage: "chart.bar.xaxis", description: Text("完成 ChatGPT 官方登录后点击刷新，或检查账号错误提示。"))
                    .frame(height: 260)
            } else {
                Chart {
                    ForEach(series) { point in
                        BarMark(
                            x: .value("日期", point.date),
                            y: .value("Token", point.value),
                            stacking: .standard
                        )
                        .foregroundStyle(by: .value("账号", point.accountName))
                        .position(by: .value("账号", point.accountName))
                        .opacity(isSelected(point.date) ? 1 : (selectedDate == nil ? 0.88 : 0.35))
                    }
                    if let selectedDate {
                        RuleMark(x: .value("选中日期", selectedDate))
                            .foregroundStyle(.secondary.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartForegroundStyleScale(domain: accounts.map(\.name), range: accounts.map { AppPalette.color(for: $0.colorIndex) })
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: days == 7 ? 7 : 8)) }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartXSelection(value: $selectedDate)
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .frame(height: 260)
            }

            HStack(spacing: 10) {
                if selectedDate != nil {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(selectedPoints) { point in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(color(for: point.accountName))
                                        .frame(width: 7, height: 7)
                                    Text(point.accountName)
                                        .foregroundStyle(.secondary)
                                    Text(Formatters.count(Int(point.value)))
                                        .fontWeight(.semibold)
                                        .monospacedDigit()
                                }
                                .font(.caption)
                            }
                        }
                    }
                    Button("清除选择") { self.selectedDate = nil }
                        .appGlassButton()
                        .controlSize(.small)
                        .font(.caption)
                } else {
                    Color.clear
                }
            }
            .padding(.horizontal, 2)
            .frame(height: 24)
            .accessibilityLabel(selectedDate.map {
                "\($0.formatted(date: .long, time: .omitted)) 使用量明细"
            } ?? "尚未选择日期")
        }
        .frame(height: 352, alignment: .top)
        .padding(18)
        .appGlassPanel(cornerRadius: 22, tint: .blue.opacity(0.04))
    }

    private var series: [ChartSeriesPoint] {
        return accounts.flatMap { account -> [ChartSeriesPoint] in
            guard let snapshot = snapshot(for: account.id) else { return [] }
            let points = days == 7 ? quotaCyclePoints(from: snapshot) : snapshot.points
            return points.map {
                ChartSeriesPoint(accountName: account.name, date: $0.date, value: Double($0.totalTokens))
            }
        }
    }

    private func quotaCyclePoints(from snapshot: AccountSnapshot) -> [UsagePoint] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: snapshot.quotaResetDate ?? .now)
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        let usageByDay = Dictionary(
            uniqueKeysWithValues: snapshot.points.map { (calendar.startOfDay(for: $0.date), $0) }
        )
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return usageByDay[date] ?? UsagePoint(
                date: date,
                requests: 0,
                inputTokens: 0,
                outputTokens: 0,
                cost: 0
            )
        }
    }

    private var selectedPoints: [ChartSeriesPoint] {
        guard let selectedDate else { return [] }
        return series.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
    }

    private var selectedValueText: String {
        guard let selectedDate else { return "移动指针查看每日明细" }
        let value = selectedPoints.reduce(0) { $0 + $1.value }
        let formatted = Formatters.count(Int(value))
        return "\(selectedDate.formatted(date: .abbreviated, time: .omitted)) · 合计 \(formatted)"
    }

    private func snapshot(for id: UUID) -> AccountSnapshot? {
        snapshots.first { $0.accountID == id }
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private func color(for accountName: String) -> Color {
        guard let account = accounts.first(where: { $0.name == accountName }) else { return .accentColor }
        return AppPalette.color(for: account.colorIndex)
    }
}

private struct ChartSeriesPoint: Identifiable {
    let accountName: String
    let date: Date
    let value: Double
    var id: String { "\(accountName)-\(date.timeIntervalSince1970)" }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .appGlassPanel(cornerRadius: 11, tint: tint.opacity(0.12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .appGlassPanel(cornerRadius: 18, tint: tint.opacity(0.06))
    }
}

struct AccountStatusCard: View {
    let account: AccountConfig
    let snapshot: AccountSnapshot?
    let isLaunching: Bool
    let onOpenCodex: () -> Void
    let onReauthenticate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Circle()
                    .fill(AppPalette.color(for: account.colorIndex))
                    .frame(width: 10, height: 10)
                Text(account.name).font(.headline)
                Spacer()
                Text(planLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .appGlassCapsule(tint: AppPalette.color(for: account.colorIndex).opacity(0.08))
            }

            if let error = snapshot?.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                HStack {
                    stat("周期 Token", Formatters.count(snapshot?.cycleTokens ?? 0))
                    Divider().frame(height: 28)
                    stat("历史 Token", Formatters.count(snapshot?.lifetimeTokens ?? 0))
                    Divider().frame(height: 28)
                    stat("连续使用", "\(snapshot?.currentStreakDays ?? 0) 天")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(snapshot?.quotaName ?? "Codex 额度").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("已用 \(Int(quotaUsed))% · 剩余 \(Int(100 - quotaUsed))%")
                        .font(.caption.weight(.medium)).monospacedDigit()
                }
                ProgressView(value: quotaUsed, total: 100)
                    .tint(quotaUsed >= 85 ? .orange : AppPalette.color(for: account.colorIndex))
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack {
                        if let reset = snapshot?.quotaResetDate {
                            Label("恢复：\(Formatters.countdown(to: reset, now: context.date))", systemImage: "clock")
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

            Divider()

            HStack {
                Label("原生对话目录 · 账号可切换", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot?.errorMessage != nil {
                    Button("重新授权", systemImage: "person.crop.circle.badge.exclamationmark") {
                        onReauthenticate()
                    }
                    .appGlassButton(tint: AppPalette.color(for: account.colorIndex).opacity(0.20))
                    .controlSize(.small)
                } else {
                    Button {
                        onOpenCodex()
                    } label: {
                        if isLaunching {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("用此账号打开 Codex", systemImage: "arrow.up.right.square")
                        }
                    }
                    .appGlassButton(tint: AppPalette.color(for: account.colorIndex).opacity(0.20))
                    .controlSize(.small)
                    .disabled(isLaunching)
                }
            }
        }
        .padding(17)
        .appGlassPanel(
            cornerRadius: 20,
            tint: AppPalette.color(for: account.colorIndex).opacity(0.05),
            interactive: true
        )
    }

    private var quotaUsed: Double { snapshot?.quotaUsedPercent ?? 0 }
    private var planLabel: String {
        guard let plan = snapshot?.planType, !plan.isEmpty else { return account.plan.rawValue }
        return plan.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
