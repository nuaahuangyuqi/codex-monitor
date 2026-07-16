import SwiftUI

@MainActor
final class AccountLoginModel: ObservableObject {
    enum State: Equatable {
        case ready
        case openingBrowser
        case waiting
        case cancelling
        case completed
        case failed(String)
    }

    @Published var state: State = .ready
    @Published var isPreparing = false
    @Published var browserError: String?
    private(set) var accountID = UUID()
    private var session: QuotioOAuthSession?
    private var currentAttemptID: UUID?
    private var preparationID: UUID?

    func prepare() async {
        guard session == nil, !isPreparing, (state == .ready || isFailure) else { return }
        let id = UUID()
        preparationID = id
        isPreparing = true
        let newSession = QuotioOAuthSession(accountID: accountID)
        session = newSession
        do {
            try await newSession.start()
            guard preparationID == id else {
                await newSession.stop()
                return
            }
            isPreparing = false
        } catch {
            guard preparationID == id else { return }
            session = nil
            preparationID = nil
            isPreparing = false
            state = .failed(error.localizedDescription)
        }
    }

    func login(store: AccountStore, onSaved: @escaping () -> Void) async {
        guard state == .ready || isFailure else { return }
        let attemptID = UUID()
        currentAttemptID = attemptID
        guard !isPreparing else { return }
        state = .openingBrowser
        browserError = nil
        let activeSession = session ?? QuotioOAuthSession(accountID: accountID)
        session = activeSession
        do {
            try await activeSession.start()
            guard currentAttemptID == attemptID else { return }
            state = .waiting
            let result = try await activeSession.loginWithChatGPT()
            guard currentAttemptID == attemptID else { return }
            await activeSession.stop()
            self.session = nil
            let displayName = result.email?.split(separator: "@").first.map(String.init) ?? "ChatGPT 账号"
            let account = AccountConfig(
                id: accountID,
                name: displayName,
                email: result.email,
                plan: tier(from: result.planType),
                quotaName: result.primaryLimit?.name ?? "Codex 额度",
                quotaUsedPercent: result.primaryLimit?.usedPercent ?? 0,
                quotaResetDate: result.primaryLimit?.resetsAt ?? .now,
                colorIndex: store.accounts.count
            )
            store.upsert(account)
            state = .completed
            onSaved()
        } catch {
            await activeSession.stop()
            guard currentAttemptID == attemptID else { return }
            self.session = nil
            currentAttemptID = nil
            QuotioOAuthSession.deleteAccountHome(id: accountID)
            accountID = UUID()
            state = .failed(error.localizedDescription)
        }
    }

    func reopenBrowser() {
        guard let session else { return }
        browserError = nil
        Task {
            do {
                try await session.reopenLoginBrowser()
            } catch {
                browserError = error.localizedDescription
            }
        }
    }

    func cancelAndReset() async {
        guard state == .waiting || state == .openingBrowser else { return }
        state = .cancelling
        currentAttemptID = nil
        preparationID = nil
        isPreparing = false
        let activeSession = session
        session = nil
        await activeSession?.cancelActiveLogin()
        QuotioOAuthSession.deleteAccountHome(id: accountID)
        accountID = UUID()
        state = .ready
        await prepare()
    }

    func cancelForDismissal() {
        guard let session else { return }
        currentAttemptID = nil
        preparationID = nil
        isPreparing = false
        self.session = nil
        let abandonedAccountID = accountID
        Task {
            await session.cancelActiveLogin()
            QuotioOAuthSession.deleteAccountHome(id: abandonedAccountID)
        }
    }

    private var isFailure: Bool {
        if case .failed = state { return true }
        return false
    }

    private func tier(from value: String) -> SubscriptionTier {
        switch value.lowercased() {
        case "plus": return .plus
        case "pro", "prolite": return .pro
        case "team", "business", "self_serve_business_usage_based", "enterprise", "enterprise_cbp_usage_based", "edu": return .business
        case "free", "go": return .free
        default: return .api
        }
    }
}

struct AccountLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: AccountStore
    @StateObject private var model = AccountLoginModel()
    let onSaved: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加 ChatGPT 账号")
                        .font(.title2.weight(.semibold))
                    Text("通过 OpenAI 官方登录授权")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") {
                    model.cancelForDismissal()
                    dismiss()
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
                VStack(spacing: 16) {
                    Image(systemName: stateIcon)
                        .font(.system(size: 42, weight: .medium))
                        .foregroundStyle(stateColor)
                    Text(stateTitle)
                        .font(.title3.weight(.semibold))
                    Text(stateDescription)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 390)
                    if model.state == .waiting || model.state == .openingBrowser || model.state == .cancelling {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(28)
            }
            .frame(height: 235)

            Label("密码和登录凭据由 Codex 官方登录服务管理，本应用不会读取浏览器 Cookie。每个账号使用独立的本机认证空间。", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let browserError = model.browserError {
                Label(browserError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                if model.state == .completed {
                    Spacer()
                    Button("完成") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else if model.state == .waiting || model.state == .openingBrowser || model.state == .cancelling {
                    Button("取消登录") {
                        Task { await model.cancelAndReset() }
                    }
                    .disabled(model.state == .cancelling)
                    Spacer()
                    Button("重新打开浏览器") { model.reopenBrowser() }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.state != .waiting)
                } else {
                    Button("关闭") { dismiss() }
                    Spacer()
                    Button(actionTitle) {
                        Task { await model.login(store: store, onSaved: onSaved) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isPreparing)
                }
            }
        }
        .padding(24)
        .frame(width: 540, height: 470)
        .task { await model.prepare() }
        .onDisappear { model.cancelForDismissal() }
    }

    private var actionTitle: String {
        if model.isPreparing { return "正在准备登录…" }
        if case .failed = model.state { return "重新登录" }
        return "前往 OpenAI 官方网站登录"
    }

    private var stateIcon: String {
        switch model.state {
        case .ready: return "person.crop.circle.badge.plus"
        case .openingBrowser, .waiting: return "safari"
        case .cancelling: return "xmark.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch model.state {
        case .completed: return .green
        case .failed: return .orange
        default: return .accentColor
        }
    }

    private var stateTitle: String {
        switch model.state {
        case .ready: return "使用 ChatGPT 登录"
        case .openingBrowser: return "正在打开浏览器"
        case .waiting: return "请在浏览器中完成登录"
        case .cancelling: return "正在取消登录"
        case .completed: return "账号添加成功"
        case .failed: return "登录未完成"
        }
    }

    private var stateDescription: String {
        switch model.state {
        case .ready:
            return model.isPreparing
                ? "正在后台预启动 OpenAI 官方认证服务，稍候即可快速打开登录页。"
                : "点击下方按钮后将立即跳转到 OpenAI 官方页面。登录完成后浏览器会显示本地成功页，并自动返回本应用。"
        case .openingBrowser:
            return "正在创建安全登录会话…"
        case .waiting:
            return "可以切回浏览器继续；如果误关浏览器，可重新打开，或取消后重新发起登录。"
        case .cancelling:
            return "正在终止当前官方登录会话并清理临时凭据…"
        case .completed:
            return "方案、Token 活动和 Codex 额度已连接。"
        case .failed(let message):
            return message
        }
    }
}
