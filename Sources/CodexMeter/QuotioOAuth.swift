// OAuth and Codex quota flow adapted from Quotio (MIT License).
// Copyright (c) 2025 Trong Nguyen. See THIRD_PARTY_NOTICES.md.

import AppKit
import Foundation

enum CodexMonitorAuthError: LocalizedError {
    case proxyBinaryMissing
    case proxyStartupFailed
    case invalidResponse
    case browserLaunchFailed
    case loginFailed(String)
    case loginCancelled
    case loginTimedOut
    case noAuthFile
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .proxyBinaryMissing: return "应用内缺少 CLIProxyAPI 登录组件"
        case .proxyStartupFailed: return "本地登录服务启动失败"
        case .invalidResponse: return "本地登录服务返回了无法识别的数据"
        case .browserLaunchFailed: return "系统未能打开默认浏览器"
        case .loginFailed(let message): return message
        case .loginCancelled: return "登录已取消"
        case .loginTimedOut: return "登录等待超时，请重新尝试"
        case .noAuthFile: return "登录完成，但没有找到 Codex 账号凭据"
        case .http(let status, let message): return "请求失败（\(status)）：\(message)"
        }
    }
}

struct CodexAccountResult: Sendable {
    let email: String?
    let planType: String
    let primaryLimit: CodexLimit?
    let secondaryLimit: CodexLimit?
    let lifetimeTokens: Int?
    let peakDailyTokens: Int?
    let currentStreakDays: Int?
    let dailyUsage: [(date: Date, tokens: Int)]
}

struct CodexLimit: Sendable {
    let name: String
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?
}

private struct OAuthURLResponse: Decodable {
    let status: String
    let url: String?
    let state: String?
    let error: String?
}

private struct OAuthStatusResponse: Decodable {
    let status: String
    let error: String?
}

actor QuotioOAuthSession {
    private let accountID: UUID
    private let managementKey = UUID().uuidString
    private let port = Int.random(in: 22_000...42_000)
    private var process: Process?
    private var activeURL: URL?
    private var cancelled = false

    init(accountID: UUID) {
        self.accountID = accountID
    }

    func start() async throws {
        guard process == nil else { return }
        cancelled = false
        let paths = try Self.paths(for: accountID)
        guard let binary = Self.proxyBinaryURL() else { throw CodexMonitorAuthError.proxyBinaryMissing }
        try Self.writeConfig(to: paths.config, authDirectory: paths.auth, port: port, managementKey: managementKey)

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = binary
        process.arguments = ["-config", paths.config.path]
        process.currentDirectoryURL = binary.deletingLastPathComponent()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData.count }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData.count }
        process.terminationHandler = { _ in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
        }
        try process.run()
        self.process = process

        // Quotio retries local management requests while the proxy starts.
        var lastError: Error = CodexMonitorAuthError.proxyStartupFailed
        for _ in 0..<30 {
            guard process.isRunning else { throw CodexMonitorAuthError.proxyStartupFailed }
            do {
                _ = try await request("/auth-files")
                return
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        stop()
        throw lastError
    }

    func loginWithChatGPT() async throws -> CodexAccountResult {
        let response: OAuthURLResponse = try await decodedRequest("/codex-auth-url?is_webui=true")
        guard response.status == "ok",
              let urlText = response.url,
              let state = response.state,
              let url = URL(string: urlText) else {
            throw CodexMonitorAuthError.loginFailed(response.error ?? "无法创建 Codex 登录链接")
        }
        activeURL = url

        // Intentionally identical to Quotio's proven macOS launch path.
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw CodexMonitorAuthError.browserLaunchFailed }

        for _ in 0..<60 {
            if cancelled { throw CodexMonitorAuthError.loginCancelled }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            if cancelled { throw CodexMonitorAuthError.loginCancelled }
            do {
                let encodedState = state.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? state
                let status: OAuthStatusResponse = try await decodedRequest("/get-auth-status?state=\(encodedState)")
                switch status.status {
                case "ok":
                    activeURL = nil
                    let result = try await QuotioAccountService.refresh(accountID: accountID)
                    stop()
                    return result
                case "error":
                    throw CodexMonitorAuthError.loginFailed(status.error ?? "Codex 登录失败")
                default:
                    continue
                }
            } catch let error as CodexMonitorAuthError {
                if case .http = error { continue }
                throw error
            } catch {
                continue
            }
        }
        throw CodexMonitorAuthError.loginTimedOut
    }

    func reopenLoginBrowser() async throws {
        guard let activeURL else { return }
        let opened = await MainActor.run { NSWorkspace.shared.open(activeURL) }
        if !opened { throw CodexMonitorAuthError.browserLaunchFailed }
    }

    func cancelActiveLogin() {
        cancelled = true
        activeURL = nil
        stop()
    }

    func stop() {
        guard let process else { return }
        self.process = nil
        if process.isRunning { process.terminate() }
    }

    private func decodedRequest<T: Decodable>(_ endpoint: String) async throws -> T {
        let data = try await request(endpoint)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw CodexMonitorAuthError.invalidResponse }
    }

    private func request(_ endpoint: String) async throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v0/management\(endpoint)") else {
            throw CodexMonitorAuthError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(managementKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("close", forHTTPHeaderField: "Connection")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        let (data, response) = try await URLSession(configuration: config).data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CodexMonitorAuthError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw CodexMonitorAuthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "未知错误")
        }
        return data
    }

    private struct Paths {
        let root: URL
        let auth: URL
        let config: URL
    }

    private static func paths(for id: UUID) throws -> Paths {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = support.appendingPathComponent("CodexMonitor/Accounts/\(id.uuidString)/Quotio", isDirectory: true)
        let auth = root.appendingPathComponent("auth", isDirectory: true)
        try FileManager.default.createDirectory(at: auth, withIntermediateDirectories: true)
        return Paths(root: root, auth: auth, config: root.appendingPathComponent("config.yaml"))
    }

    private static func writeConfig(to url: URL, authDirectory: URL, port: Int, managementKey: String) throws {
        let content = """
        host: "127.0.0.1"
        port: \(port)
        auth-dir: "\(authDirectory.path)"
        proxy-url: ""

        api-keys:
          - "codex-monitor-local"

        remote-management:
          allow-remote: false
          secret-key: "\(managementKey)"

        debug: false
        logging-to-file: false
        usage-statistics-enabled: true

        routing:
          strategy: "round-robin"

        request-retry: 3
        max-retry-interval: 30
        """
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func proxyBinaryURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "cli-proxy-api-plus", withExtension: nil) {
            return bundled
        }
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "cli-proxy-api-plus", withExtension: nil, subdirectory: "Resources")
            ?? Bundle.module.url(forResource: "cli-proxy-api-plus", withExtension: nil)
        #else
        return nil
        #endif
    }

    static func deleteAccountHome(id: UUID) {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false) else { return }
        try? FileManager.default.removeItem(at: support.appendingPathComponent("CodexMonitor/Accounts/\(id.uuidString)"))
    }

    fileprivate static func authDirectory(for id: UUID) throws -> URL {
        try paths(for: id).auth
    }
}

enum QuotioAccountService {
    static func login(accountID: UUID) async throws -> CodexAccountResult {
        let session = QuotioOAuthSession(accountID: accountID)
        try await session.start()
        do {
            return try await session.loginWithChatGPT()
        } catch {
            await session.stop()
            throw error
        }
    }

    static func refresh(accountID: UUID) async throws -> CodexAccountResult {
        let authDirectory = try QuotioOAuthSession.authDirectory(for: accountID)
        let files = try FileManager.default.contentsOfDirectory(at: authDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("codex-") && $0.pathExtension == "json" }
        guard let authFile = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else {
            throw CodexMonitorAuthError.noAuthFile
        }
        let data = try Data(contentsOf: authFile)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw CodexMonitorAuthError.noAuthFile
        }
        let idPayload = (json["id_token"] as? String).flatMap(decodeJWT)
        let authPayload = idPayload?["https://api.openai.com/auth"] as? [String: Any]
        let accountID = (json["account_id"] as? String)
            ?? (json["chatgpt_account_id"] as? String)
            ?? (authPayload?["chatgpt_account_id"] as? String)
        let email = (json["email"] as? String) ?? (idPayload?["email"] as? String)
        let tokenPlan = (authPayload?["chatgpt_plan_type"] as? String)
            ?? (idPayload?["chatgpt_plan_type"] as? String)
            ?? "unknown"

        let usage = try await fetchQuota(accessToken: accessToken, accountID: accountID)
        let plan = (usage["plan_type"] as? String) ?? tokenPlan
        let rateLimit = usage["rate_limit"] as? [String: Any]
        let primary = parseWindow(rateLimit?["primary_window"], name: "Codex 5 小时额度")
        let secondary = parseWindow(rateLimit?["secondary_window"], name: "Codex 周额度")

        return CodexAccountResult(
            email: email,
            planType: plan,
            primaryLimit: primary,
            secondaryLimit: secondary,
            lifetimeTokens: nil,
            peakDailyTokens: nil,
            currentStreakDays: nil,
            dailyUsage: []
        )
    }

    private static func fetchQuota(accessToken: String, accountID: String?) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CodexMonitorAuthError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw CodexMonitorAuthError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "额度请求失败")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexMonitorAuthError.invalidResponse
        }
        return json
    }

    private static func parseWindow(_ value: Any?, name: String) -> CodexLimit? {
        guard let object = value as? [String: Any], let used = number(object["used_percent"]) else { return nil }
        let reset = number(object["reset_at"]).map { Date(timeIntervalSince1970: $0) }
        let seconds = number(object["limit_window_seconds"]).map(Int.init)
        return CodexLimit(name: name, usedPercent: used, resetsAt: reset, windowMinutes: seconds.map { $0 / 60 })
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private static func decodeJWT(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
