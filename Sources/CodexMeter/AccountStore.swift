import Foundation

@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var accounts: [AccountConfig] = []
    private let defaults: UserDefaults
    private let storageKey = "codexmeter.accounts.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func upsert(_ account: AccountConfig) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        persist()
    }

    func delete(_ account: AccountConfig) {
        accounts.removeAll { $0.id == account.id }
        QuotioOAuthSession.deleteAccountHome(id: account.id)
        persist()
    }

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([AccountConfig].self, from: data) else { return }
        accounts = decoded
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
