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
                        let result = try await QuotioAccountService.refresh(accountID: account.id)
                        let cutoff = Calendar.current.date(byAdding: .day, value: -days + 1, to: Calendar.current.startOfDay(for: .now)) ?? .distantPast
                        let points = result.dailyUsage.filter { $0.date >= cutoff }.map {
                            UsagePoint(date: $0.date, requests: 0, inputTokens: $0.tokens, outputTokens: 0, cost: 0)
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
        let validIDs = Set(accounts.map(\.id))
        snapshots = snapshots.filter { validIDs.contains($0.key) }
    }

    func remove(accountID: UUID) {
        snapshots.removeValue(forKey: accountID)
    }
}
