import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    static let historyDays = 30
    @Published private(set) var snapshots: [UUID: AccountSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published var days = 30
    private var hasPerformedInitialRefresh = false
    private let defaults: UserDefaults
    private let baselineStorageKey = "codexmeter.usage-baselines.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func refreshInitial30Days(accounts: [AccountConfig]) async {
        guard !hasPerformedInitialRefresh else { return }
        hasPerformedInitialRefresh = true
        await refresh(accounts: accounts)
    }

    func refresh(accounts: [AccountConfig]) async {
        guard !isRefreshing, !accounts.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let historyDays = Self.historyDays
        let baselines = loadBaselines()
        await withTaskGroup(of: AccountSnapshot.self) { group in
            for account in accounts {
                let baseline = baselines[account.id.uuidString]
                group.addTask {
                    do {
                        let result = try await CodexAccountService.refresh(accountID: account.id)
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: .now)
                        let cutoff = calendar.date(byAdding: .day, value: -historyDays + 1, to: today) ?? .distantPast
                        let usageByDay = Dictionary(
                            result.dailyUsage.filter { $0.date >= cutoff }.map {
                                (calendar.startOfDay(for: $0.date), $0.tokens)
                            },
                            uniquingKeysWith: +
                        )
                        let points = (0..<historyDays).compactMap { offset -> UsagePoint? in
                            guard let date = calendar.date(byAdding: .day, value: offset, to: cutoff) else { return nil }
                            return UsagePoint(
                                date: date,
                                requests: 0,
                                inputTokens: usageByDay[date] ?? 0,
                                outputTokens: 0,
                                cost: 0
                            )
                        }
                        let refreshedAt = Date.now
                        let cycleTokens = result.lifetimeTokens.map { lifetime in
                            guard let baseline else { return 0 }
                            return max(lifetime - baseline.lifetimeTokens, 0)
                        }
                        return AccountSnapshot(
                            accountID: account.id,
                            points: points,
                            lastUpdated: refreshedAt,
                            errorMessage: nil,
                            planType: result.planType,
                            quotaName: result.primaryLimit?.name,
                            quotaUsedPercent: result.primaryLimit?.usedPercent,
                            quotaResetDate: result.primaryLimit?.resetsAt,
                            secondaryQuotaUsedPercent: result.secondaryLimit?.usedPercent,
                            secondaryQuotaResetDate: result.secondaryLimit?.resetsAt,
                            lifetimeTokens: result.lifetimeTokens,
                            peakDailyTokens: result.peakDailyTokens,
                            currentStreakDays: result.currentStreakDays,
                            cycleTokens: cycleTokens,
                            cycleStartedAt: baseline?.refreshedAt
                        )
                    } catch {
                        return AccountSnapshot(
                            accountID: account.id,
                            points: [],
                            lastUpdated: nil,
                            errorMessage: error.localizedDescription
                        )
                    }
                }
            }
            for await snapshot in group {
                snapshots[snapshot.accountID] = snapshot
            }
        }
        var updatedBaselines = baselines
        for account in accounts {
            guard let snapshot = snapshots[account.id],
                  snapshot.errorMessage == nil,
                  let lifetimeTokens = snapshot.lifetimeTokens,
                  let refreshedAt = snapshot.lastUpdated else { continue }
            updatedBaselines[account.id.uuidString] = UsageBaseline(
                lifetimeTokens: lifetimeTokens,
                refreshedAt: refreshedAt
            )
        }
        saveBaselines(updatedBaselines)
    }

    func remove(accountID: UUID) {
        snapshots.removeValue(forKey: accountID)
        var baselines = loadBaselines()
        baselines.removeValue(forKey: accountID.uuidString)
        saveBaselines(baselines)
    }

    private func loadBaselines() -> [String: UsageBaseline] {
        guard let data = defaults.data(forKey: baselineStorageKey),
              let baselines = try? JSONDecoder().decode([String: UsageBaseline].self, from: data) else { return [:] }
        return baselines
    }

    private func saveBaselines(_ baselines: [String: UsageBaseline]) {
        guard let data = try? JSONEncoder().encode(baselines) else { return }
        defaults.set(data, forKey: baselineStorageKey)
    }
}

private struct UsageBaseline: Codable, Sendable {
    let lifetimeTokens: Int
    let refreshedAt: Date
}
