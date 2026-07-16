import Foundation

@MainActor
final class DashboardModel: ObservableObject {
    @Published private(set) var snapshots: [UUID: AccountSnapshot] = [:]
    @Published private(set) var isRefreshing = false
    @Published var days = 30

    init() {}

    func refresh(accounts: [AccountConfig]) async {
        guard !isRefreshing, !accounts.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let days = days
        await withTaskGroup(of: AccountSnapshot.self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let result = try await CodexAccountService.refresh(accountID: account.id)
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: .now)
                        let cutoff = calendar.date(byAdding: .day, value: -days + 1, to: today) ?? .distantPast
                        let usageByDay = Dictionary(
                            result.dailyUsage.filter { $0.date >= cutoff }.map {
                                (calendar.startOfDay(for: $0.date), $0.tokens)
                            },
                            uniquingKeysWith: +
                        )
                        let points = (0..<days).compactMap { offset -> UsagePoint? in
                            guard let date = calendar.date(byAdding: .day, value: offset, to: cutoff) else { return nil }
                            return UsagePoint(
                                date: date,
                                requests: 0,
                                inputTokens: usageByDay[date] ?? 0,
                                outputTokens: 0,
                                cost: 0
                            )
                        }
                        return AccountSnapshot(
                            accountID: account.id,
                            points: points,
                            lastUpdated: .now,
                            errorMessage: nil,
                            planType: result.planType,
                            quotaName: result.primaryLimit?.name,
                            quotaUsedPercent: result.primaryLimit?.usedPercent,
                            quotaResetDate: result.primaryLimit?.resetsAt,
                            secondaryQuotaUsedPercent: result.secondaryLimit?.usedPercent,
                            secondaryQuotaResetDate: result.secondaryLimit?.resetsAt,
                            lifetimeTokens: result.lifetimeTokens,
                            peakDailyTokens: result.peakDailyTokens,
                            currentStreakDays: result.currentStreakDays
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
    }

    func remove(accountID: UUID) {
        snapshots.removeValue(forKey: accountID)
    }
}
