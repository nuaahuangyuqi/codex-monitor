import Foundation

enum Formatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static let compact: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func money(_ value: Double) -> String {
        currency.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    static func count(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return value.formatted()
        }
    }

    static func countdown(to date: Date, now: Date = .now) -> String {
        guard date > now else { return "等待更新" }
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: now, to: date)
        if let day = components.day, day > 0 {
            return "\(day)天 \(components.hour ?? 0)小时"
        }
        return "\(components.hour ?? 0)小时 \(components.minute ?? 0)分钟"
    }
}
