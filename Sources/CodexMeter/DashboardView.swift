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
                chartCard
                usageTableCard

                if accounts.count > 1 {
                    Text("账号概览")
                        .font(.title3.weight(.semibold))
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
                } else if let account = accounts.first {
                    AccountStatusCard(
                        account: account,
                        snapshot: snapshot(for: account.id),
                        isLaunching: launchingAccountID == account.id,
                        onOpenCodex: { onOpenCodex(account) },
                        onReauthenticate: { onReauthenticate(account) }
                    )
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(accounts.count == 1 ? accounts[0].name : "全部账号")
                    .font(.largeTitle.weight(.bold))
                Text("最近 \(days) 天 · \(accounts.count) 个账号")
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
        HStack(spacing: 14) {
            MetricCard(title: "周期 Token", value: Formatters.count(snapshots.totalTokens), icon: "text.word.spacing", tint: .blue)
            MetricCard(title: "历史 Token", value: Formatters.count(snapshots.compactMap(\.lifetimeTokens).reduce(0, +)), icon: "clock.arrow.circlepath", tint: .purple)
            MetricCard(title: "单日峰值", value: Formatters.count(snapshots.compactMap(\.peakDailyTokens).max() ?? 0), icon: "chart.line.uptrend.xyaxis", tint: .teal)
            MetricCard(title: "账号", value: "\(accounts.count)", icon: "person.2.fill", tint: .orange)
        }
    }

    private var availabilityNote: some View {
        Label("网页登录可同步 ChatGPT/Codex 方案、Token 活动和模型额度。API 调用次数与美元费用属于 OpenAI Platform 组织接口，网页登录不会返回这两项。", systemImage: "info.circle.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("趋势")
                        .font(.headline)
                    Text(selectedValueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Text("Token")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }

            if series.isEmpty {
                ContentUnavailableView("暂无 Token 活动", systemImage: "chart.xyaxis.line", description: Text("完成 ChatGPT 官方登录后刷新，或检查账号错误提示。"))
                    .frame(height: 230)
            } else {
                Chart(series) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("Token", point.value)
                    )
                    .foregroundStyle(by: .value("账号", point.accountName))
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("日期", point.date),
                        y: .value("Token", point.value)
                    )
                    .foregroundStyle(by: .value("账号", point.accountName))
                    .opacity(accounts.count == 1 ? 0.10 : 0.025)

                    if let selectedDate, Calendar.current.isDate(point.date, inSameDayAs: selectedDate) {
                        PointMark(x: .value("日期", point.date), y: .value("Token", point.value))
                            .foregroundStyle(by: .value("账号", point.accountName))
                            .symbolSize(70)
                    }
                }
                .chartForegroundStyleScale(domain: accounts.map(\.name), range: accounts.map { AppPalette.color(for: $0.colorIndex) })
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartXSelection(value: $selectedDate)
                .frame(height: 260)
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.35), lineWidth: 1))
    }

    private var usageTableCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("每日使用量")
                        .font(.headline)
                    Text("按日期列出各账号的 Codex Token 活动")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(usageRows.count) 条")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if usageRows.isEmpty {
                ContentUnavailableView(
                    "暂无每日数据",
                    systemImage: "tablecells",
                    description: Text("刷新账号后，每日 Token 使用量会显示在这里。")
                )
                .frame(height: 150)
            } else {
                Table(usageRows) {
                    TableColumn("日期") { row in
                        Text(row.date.formatted(date: .abbreviated, time: .omitted))
                            .monospacedDigit()
                    }
                    .width(min: 120, ideal: 150)

                    TableColumn("账号") { row in
                        HStack(spacing: 7) {
                            Circle()
                                .fill(AppPalette.color(for: row.colorIndex))
                                .frame(width: 7, height: 7)
                            Text(row.accountName)
                        }
                    }

                    TableColumn("Token") { row in
                        Text(Formatters.count(row.tokens))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 100, ideal: 130)
                }
                .frame(height: min(CGFloat(usageRows.count * 34 + 34), 310))
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.35), lineWidth: 1))
    }

    private var series: [ChartSeriesPoint] {
        accounts.flatMap { account in
            (snapshot(for: account.id)?.points ?? []).map { point in
                ChartSeriesPoint(accountName: account.name, date: point.date, value: Double(point.totalTokens))
            }
        }
    }

    private var usageRows: [UsageTableRow] {
        accounts.flatMap { account in
            (snapshot(for: account.id)?.points ?? []).map { point in
                UsageTableRow(
                    accountID: account.id,
                    accountName: account.name,
                    colorIndex: account.colorIndex,
                    date: point.date,
                    tokens: point.totalTokens
                )
            }
        }
        .sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.accountName.localizedStandardCompare($1.accountName) == .orderedAscending
        }
    }

    private var selectedValueText: String {
        guard let selectedDate else { return "移动指针查看每日明细" }
        let points = series.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }
        let value = points.reduce(0) { $0 + $1.value }
        let formatted = Formatters.count(Int(value))
        return "\(selectedDate.formatted(date: .abbreviated, time: .omitted)) · 合计 \(formatted)"
    }

    private func snapshot(for id: UUID) -> AccountSnapshot? {
        snapshots.first { $0.accountID == id }
    }
}

private struct ChartSeriesPoint: Identifiable {
    let accountName: String
    let date: Date
    let value: Double
    var id: String { "\(accountName)-\(date.timeIntervalSince1970)" }
}

private struct UsageTableRow: Identifiable {
    let accountID: UUID
    let accountName: String
    let colorIndex: Int
    let date: Date
    let tokens: Int
    var id: String { "\(accountID.uuidString)-\(date.timeIntervalSince1970)" }
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
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.separator.opacity(0.35), lineWidth: 1))
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
                    .background(.quaternary, in: Capsule())
            }

            if let error = snapshot?.errorMessage {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            } else {
                HStack {
                    stat("周期 Token", Formatters.count(snapshot?.totalTokens ?? 0))
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
                Label("独立账号空间", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot?.errorMessage != nil {
                    Button("重新授权", systemImage: "person.crop.circle.badge.exclamationmark") {
                        onReauthenticate()
                    }
                    .buttonStyle(.borderedProminent)
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
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isLaunching)
                }
            }
        }
        .padding(17)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.35), lineWidth: 1))
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
