import Foundation
import SwiftUI

enum SubscriptionTier: String, Codable, CaseIterable, Identifiable, Sendable {
    case free = "Free"
    case plus = "Plus"
    case pro = "Pro"
    case business = "Business"
    case api = "API only"

    var id: String { rawValue }
}

struct AccountConfig: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var email: String?
    var organizationID: String
    var plan: SubscriptionTier
    var renewalDate: Date
    var quotaName: String
    var quotaUsedPercent: Double
    var quotaResetDate: Date
    var monthlyBudget: Double
    var colorIndex: Int

    init(
        id: UUID = UUID(),
        name: String,
        email: String? = nil,
        organizationID: String = "",
        plan: SubscriptionTier = .api,
        renewalDate: Date = .now,
        quotaName: String = "Codex 模型额度",
        quotaUsedPercent: Double = 0,
        quotaResetDate: Date = .now.addingTimeInterval(5 * 24 * 3600),
        monthlyBudget: Double = 0,
        colorIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.organizationID = organizationID
        self.plan = plan
        self.renewalDate = renewalDate
        self.quotaName = quotaName
        self.quotaUsedPercent = min(max(quotaUsedPercent, 0), 100)
        self.quotaResetDate = quotaResetDate
        self.monthlyBudget = max(monthlyBudget, 0)
        self.colorIndex = colorIndex
    }
}

struct UsagePoint: Identifiable, Hashable, Sendable {
    let date: Date
    var requests: Int
    var inputTokens: Int
    var outputTokens: Int
    var cost: Double

    var id: Date { date }
    var totalTokens: Int { inputTokens + outputTokens }
}

struct AccountSnapshot: Sendable {
    let accountID: UUID
    var points: [UsagePoint]
    var lastUpdated: Date?
    var errorMessage: String?
    var planType: String? = nil
    var quotaName: String? = nil
    var quotaUsedPercent: Double? = nil
    var quotaResetDate: Date? = nil
    var secondaryQuotaUsedPercent: Double? = nil
    var secondaryQuotaResetDate: Date? = nil
    var lifetimeTokens: Int? = nil
    var peakDailyTokens: Int? = nil
    var currentStreakDays: Int? = nil

    var requests: Int { points.reduce(0) { $0 + $1.requests } }
    var inputTokens: Int { points.reduce(0) { $0 + $1.inputTokens } }
    var outputTokens: Int { points.reduce(0) { $0 + $1.outputTokens } }
    var totalTokens: Int { inputTokens + outputTokens }
    var cost: Double { points.reduce(0) { $0 + $1.cost } }
}

extension Array where Element == AccountSnapshot {
    var totalRequests: Int { reduce(0) { $0 + $1.requests } }
    var totalTokens: Int { reduce(0) { $0 + $1.totalTokens } }
    var totalCost: Double { reduce(0) { $0 + $1.cost } }
}

enum AppPalette {
    static let colors: [Color] = [
        Color(red: 0.18, green: 0.47, blue: 0.98),
        Color(red: 0.45, green: 0.31, blue: 0.91),
        Color(red: 0.04, green: 0.64, blue: 0.55),
        Color(red: 0.96, green: 0.48, blue: 0.18),
        Color(red: 0.90, green: 0.25, blue: 0.42),
        Color(red: 0.18, green: 0.65, blue: 0.86)
    ]

    static func color(for index: Int) -> Color {
        colors[abs(index) % colors.count]
    }
}
