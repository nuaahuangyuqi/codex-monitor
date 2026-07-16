import AppKit
import Darwin
import Foundation

enum CodexAppServerError: LocalizedError {
    case binaryMissing
    case appMissing
    case processLaunchFailed(String)
    case processEnded
    case browserLaunchFailed
    case invalidResponse(String)
    case rpc(String)
    case notAuthenticated
    case loginFailed(String)
    case credentialMissing
    case credentialStoreUnsupported(String)
    case nativeHomeRedirected(String)
    case codexDidNotQuit

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "没有找到 Codex。请先安装或更新 Codex macOS 应用。"
        case .appMissing:
            return "没有找到 Codex macOS 应用。"
        case .processLaunchFailed(let message):
            return "Codex 本地服务启动失败：\(message)"
        case .processEnded:
            return "Codex 本地服务已意外退出"
        case .browserLaunchFailed:
            return "系统未能打开默认浏览器"
        case .invalidResponse(let message):
            return "Codex 返回了无法识别的数据：\(message)"
        case .rpc(let message):
            return message
        case .notAuthenticated:
            return "账号尚未完成 Codex 官方授权，请重新登录"
        case .loginFailed(let message):
            return message
        case .credentialMissing:
            return "该账号没有可用的 Codex 登录凭据，请重新授权"
        case .credentialStoreUnsupported(let value):
            return "Codex 当前使用 \(value) 凭据存储。一键切换需要在 ~/.codex/config.toml 中使用 cli_auth_credentials_store = \"file\"。"
        case .nativeHomeRedirected(let value):
            return "Codex 的 SQLite 状态被重定向到 \(value)。请删除 ~/.codex/config.toml 中的 sqlite_home 设置后再试。"
        case .codexDidNotQuit:
            return "Codex 未能完全退出。为避免账号和对话状态损坏，本次切换已取消。"
        }
    }
}

indirect enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var intValue: Int? { doubleValue.map(Int.init) }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}

enum CodexCredentialVault {
    private static let manager = FileManager.default

    static func migrateLegacy(accounts: [AccountConfig]) {
        guard let support = try? supportURL(create: true) else { return }
        let accountsRoot = support.appendingPathComponent("Accounts", isDirectory: true)
        let nativeAuth = try? Data(contentsOf: CodexNativeHome.authURL)
        let nativeExternalID = nativeAuth.flatMap(externalAccountID)
        var credentialsSecured = true

        for account in accounts {
            let accountRoot = accountsRoot.appendingPathComponent(account.id.uuidString, isDirectory: true)
            let existing = try? load(accountID: account.id)
            let candidate = legacyAuthData(accountRoot: accountRoot) ?? existing
            let candidateExternalID = candidate.flatMap(externalAccountID)

            let selected = (nativeExternalID != nil && nativeExternalID == candidateExternalID)
                ? nativeAuth
                : candidate
            if let selected {
                do { try save(selected, accountID: account.id) }
                catch { credentialsSecured = false }
            } else if manager.fileExists(atPath: accountRoot.path) {
                credentialsSecured = false
            }
        }

        // 旧 Accounts 目录是完整的隔离 CODEX_HOME。凭据导出后整体删除，
        // 故意放弃其中独有的会话、SQLite、缓存和旧备份。
        if credentialsSecured { try? manager.removeItem(at: accountsRoot) }
    }

    static func save(_ data: Data, accountID: UUID) throws {
        guard externalAccountID(from: data) != nil else {
            throw CodexAppServerError.invalidResponse("账号凭据缺少 account_id")
        }
        let directory = try credentialsURL(create: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try atomicWrite(data, to: directory.appendingPathComponent("\(accountID.uuidString).auth.json"))
    }

    static func load(accountID: UUID) throws -> Data {
        let file = try credentialsURL(create: false)
            .appendingPathComponent("\(accountID.uuidString).auth.json")
        guard manager.fileExists(atPath: file.path) else { throw CodexAppServerError.credentialMissing }
        let data = try Data(contentsOf: file)
        guard externalAccountID(from: data) != nil else { throw CodexAppServerError.credentialMissing }
        return data
    }

    static func delete(accountID: UUID) {
        guard let directory = try? credentialsURL(create: false) else { return }
        try? manager.removeItem(at: directory.appendingPathComponent("\(accountID.uuidString).auth.json"))
    }

    static func externalAccountID(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = object["tokens"] as? [String: Any] else { return nil }
        return tokens["account_id"] as? String
    }

    static func atomicWrite(_ data: Data, to destination: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            let handle = try FileHandle(forWritingTo: temporary)
            try handle.synchronize()
            try handle.close()
            if rename(temporary.path, destination.path) != 0 {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    private static func legacyAuthData(accountRoot: URL) -> Data? {
        let candidates = [
            accountRoot.appendingPathComponent("CodexHome/auth.json"),
            accountRoot.appendingPathComponent("auth.json")
        ]
        for candidate in candidates {
            if let data = try? Data(contentsOf: candidate), externalAccountID(from: data) != nil {
                return data
            }
        }

        let legacyDirectory = accountRoot.appendingPathComponent("Quotio/auth", isDirectory: true)
        guard let files = try? manager.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil),
              let source = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first(where: {
                  $0.lastPathComponent.hasPrefix("codex-") && $0.pathExtension == "json"
              }),
              let data = try? Data(contentsOf: source),
              let legacy = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = legacy["id_token"] as? String,
              let accessToken = legacy["access_token"] as? String,
              let refreshToken = legacy["refresh_token"] as? String,
              let externalID = legacy["account_id"] as? String else { return nil }

        let auth: [String: Any] = [
            "OPENAI_API_KEY": NSNull(),
            "auth_mode": "chatgpt",
            "tokens": [
                "id_token": idToken,
                "access_token": accessToken,
                "refresh_token": refreshToken,
                "account_id": externalID
            ],
            "last_refresh": (legacy["last_refresh"] as? String) ?? ISO8601DateFormatter().string(from: .now)
        ]
        return try? JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted, .sortedKeys])
    }

    private static func supportURL(create: Bool) throws -> URL {
        try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        ).appendingPathComponent("CodexMonitor", isDirectory: true)
    }

    private static func credentialsURL(create: Bool) throws -> URL {
        let directory = try supportURL(create: create).appendingPathComponent("Credentials", isDirectory: true)
        if create { try manager.createDirectory(at: directory, withIntermediateDirectories: true) }
        return directory
    }
}

enum CodexNativeHome {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true)
    static let authURL = url.appendingPathComponent("auth.json")

    static func validateConfiguration() throws {
        let config = url.appendingPathComponent("config.toml")
        guard let text = try? String(contentsOf: config, encoding: .utf8) else { return }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if key == "cli_auth_credentials_store", value != "file" {
                throw CodexAppServerError.credentialStoreUnsupported(value)
            }
            if key == "sqlite_home" {
                let redirected = URL(fileURLWithPath: NSString(string: value).expandingTildeInPath).standardizedFileURL
                if redirected != url.standardizedFileURL {
                    throw CodexAppServerError.nativeHomeRedirected(value)
                }
            }
        }
    }
}

struct CodexRuntimeHome: Sendable {
    let url: URL

    static func create(authData: Data? = nil) throws -> CodexRuntimeHome {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexMonitor", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        try Data("cli_auth_credentials_store = \"file\"\n".utf8)
            .write(to: root.appendingPathComponent("config.toml"), options: .atomic)
        if let authData {
            try CodexCredentialVault.atomicWrite(authData, to: root.appendingPathComponent("auth.json"))
        }
        return CodexRuntimeHome(url: root)
    }

    func persistCredential(accountID: UUID) throws {
        let auth = url.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: auth.path) else { throw CodexAppServerError.credentialMissing }
        try CodexCredentialVault.save(Data(contentsOf: auth), accountID: accountID)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

enum CodexBinaryLocator {
    static func executableURL() -> URL? {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        ]
        return candidates.first { manager.isExecutableFile(atPath: $0.path) }
    }
}

actor CodexAppServerClient {
    private let homeURL: URL
    private let process = Process()
    private let inputPipe = Pipe()
    private let outputPipe = Pipe()
    private let errorPipe = Pipe()
    private var readerTask: Task<Void, Never>?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var loginWaiters: [String: CheckedContinuation<JSONValue, Error>] = [:]
    private var completedLogins: [String: JSONValue] = [:]
    private var stopped = false

    init(homeURL: URL) {
        self.homeURL = homeURL
    }

    static func start(homeURL: URL) async throws -> CodexAppServerClient {
        let client = CodexAppServerClient(homeURL: homeURL)
        do {
            try await client.launch()
            return client
        } catch {
            await client.stop()
            throw error
        }
    }

    private func launch() async throws {
        guard let executable = CodexBinaryLocator.executableURL() else { throw CodexAppServerError.binaryMissing }
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = homeURL.path
        environment["CODEX_SQLITE_HOME"] = homeURL.path
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.environment = environment
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        errorPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        do { try process.run() }
        catch { throw CodexAppServerError.processLaunchFailed(error.localizedDescription) }

        let output = outputPipe.fileHandleForReading
        readerTask = Task { [weak self] in
            do {
                for try await line in output.bytes.lines {
                    await self?.receive(line: line)
                }
                await self?.failAll(with: CodexAppServerError.processEnded)
            } catch {
                await self?.failAll(with: error)
            }
        }

        _ = try await request("initialize", params: .object([
            "clientInfo": .object([
                "name": .string("codex_monitor"),
                "title": .string("Codex Monitor"),
                "version": .string("1.0")
            ]),
            "capabilities": .object([:])
        ]))
        try sendNotification("initialized", params: nil)
    }

    func request(_ method: String, params: JSONValue? = nil) async throws -> JSONValue {
        guard !stopped else { throw CodexAppServerError.processEnded }
        let id = nextID
        nextID += 1
        var object: [String: JSONValue] = [
            "id": .number(Double(id)),
            "method": .string(method)
        ]
        if let params { object["params"] = params }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try write(.object(object)) }
            catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    func waitForLogin(id: String) async throws -> JSONValue {
        if let completed = completedLogins.removeValue(forKey: id) { return completed }
        return try await withCheckedThrowingContinuation { continuation in
            loginWaiters[id] = continuation
        }
    }

    func cancelLogin(id: String) async {
        _ = try? await request("account/login/cancel", params: .object(["loginId": .string(id)]))
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        readerTask?.cancel()
        readerTask = nil
        try? inputPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        errorPipe.fileHandleForReading.readabilityHandler = nil
        failAll(with: CodexAppServerError.processEnded)
    }

    private func sendNotification(_ method: String, params: JSONValue?) throws {
        var object: [String: JSONValue] = ["method": .string(method)]
        if let params { object["params"] = params }
        try write(.object(object))
    }

    private func write(_ value: JSONValue) throws {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        try inputPipe.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(line: String) {
        guard let data = line.data(using: .utf8),
              let message = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }

        if let id = message["id"]?.intValue, let continuation = pending.removeValue(forKey: id) {
            if let result = message["result"] {
                continuation.resume(returning: result)
            } else {
                let error = message["error"]?["message"]?.stringValue ?? "Codex 请求失败"
                continuation.resume(throwing: CodexAppServerError.rpc(error))
            }
            return
        }

        guard message["method"]?.stringValue == "account/login/completed",
              let params = message["params"],
              let loginID = params["loginId"]?.stringValue else { return }
        if let continuation = loginWaiters.removeValue(forKey: loginID) {
            continuation.resume(returning: params)
        } else {
            completedLogins[loginID] = params
        }
    }

    private func failAll(with error: Error) {
        let requestContinuations = pending.values
        let loginContinuations = loginWaiters.values
        pending.removeAll()
        loginWaiters.removeAll()
        for continuation in requestContinuations { continuation.resume(throwing: error) }
        for continuation in loginContinuations { continuation.resume(throwing: error) }
    }
}

actor CodexOAuthSession {
    private let accountID: UUID
    private var client: CodexAppServerClient?
    private var runtime: CodexRuntimeHome?
    private var activeURL: URL?
    private var loginID: String?

    init(accountID: UUID) {
        self.accountID = accountID
    }

    func start() async throws {
        guard client == nil else { return }
        let runtime = try CodexRuntimeHome.create()
        do {
            client = try await CodexAppServerClient.start(homeURL: runtime.url)
            self.runtime = runtime
        } catch {
            runtime.remove()
            throw error
        }
    }

    func loginWithChatGPT() async throws -> CodexAccountResult {
        try await start()
        guard let client else { throw CodexAppServerError.processEnded }
        let response = try await client.request("account/login/start", params: .object([
            "type": .string("chatgpt"),
            "useHostedLoginSuccessPage": .bool(true),
            "appBrand": .string("codex")
        ]))
        guard let urlText = response["authUrl"]?.stringValue,
              let url = URL(string: urlText),
              let loginID = response["loginId"]?.stringValue else {
            throw CodexAppServerError.invalidResponse("登录链接缺失")
        }
        activeURL = url
        self.loginID = loginID
        let opened = await MainActor.run { NSWorkspace.shared.open(url) }
        guard opened else { throw CodexAppServerError.browserLaunchFailed }

        let completion = try await client.waitForLogin(id: loginID)
        guard completion["success"]?.boolValue == true else {
            throw CodexAppServerError.loginFailed(completion["error"]?.stringValue ?? "Codex 登录失败")
        }
        activeURL = nil
        self.loginID = nil
        await client.stop()
        self.client = nil
        guard let runtime else { throw CodexAppServerError.credentialMissing }
        do {
            try await CodexAccountCoordinator.shared.importCredential(from: runtime, accountID: accountID)
            runtime.remove()
            self.runtime = nil
        } catch {
            runtime.remove()
            self.runtime = nil
            throw error
        }
        return try await CodexAccountService.refresh(accountID: accountID)
    }

    func reopenLoginBrowser() async throws {
        guard let activeURL else { return }
        let opened = await MainActor.run { NSWorkspace.shared.open(activeURL) }
        if !opened { throw CodexAppServerError.browserLaunchFailed }
    }

    func cancelActiveLogin() async {
        if let loginID, let client { await client.cancelLogin(id: loginID) }
        activeURL = nil
        loginID = nil
        await stop()
    }

    func stop() async {
        if let client {
            self.client = nil
            await client.stop()
        }
        runtime?.remove()
        runtime = nil
    }
}

actor CodexOperationGate {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

actor CodexAccountCoordinator {
    static let shared = CodexAccountCoordinator()
    private let gate = CodexOperationGate()

    func refresh(accountID: UUID) async throws -> CodexAccountResult {
        await gate.acquire()
        do {
            let result = try await refreshUnlocked(accountID: accountID)
            await gate.release()
            return result
        } catch {
            await gate.release()
            throw error
        }
    }

    func validate(accountID: UUID) async throws {
        await gate.acquire()
        do {
            try await validateUnlocked(accountID: accountID)
            await gate.release()
        } catch {
            await gate.release()
            throw error
        }
    }

    func importCredential(from runtime: CodexRuntimeHome, accountID: UUID) async throws {
        await gate.acquire()
        do {
            try runtime.persistCredential(accountID: accountID)
            await gate.release()
        } catch {
            await gate.release()
            throw error
        }
    }

    private func refreshUnlocked(accountID: UUID) async throws -> CodexAccountResult {
        let context = try makeContext(accountID: accountID)
        let client: CodexAppServerClient
        do {
            client = try await CodexAppServerClient.start(homeURL: context.homeURL)
        } catch {
            context.runtime?.remove()
            throw error
        }

        do {
            let account = try await client.request("account/read", params: .object(["refreshToken": .bool(false)]))
            guard account["account"]?["type"]?.stringValue == "chatgpt" else {
                throw CodexAppServerError.notAuthenticated
            }
            async let limitsRequest = client.request("account/rateLimits/read")
            async let usageRequest = client.request("account/usage/read")
            let (limits, usage) = try await (limitsRequest, usageRequest)
            await client.stop()
            try persist(context: context, accountID: accountID)
            return CodexAccountService.parse(account: account, limits: limits, usage: usage)
        } catch {
            await client.stop()
            try? persist(context: context, accountID: accountID)
            throw error
        }
    }

    private func validateUnlocked(accountID: UUID) async throws {
        let context = try makeContext(accountID: accountID)
        let client: CodexAppServerClient
        do {
            client = try await CodexAppServerClient.start(homeURL: context.homeURL)
        } catch {
            context.runtime?.remove()
            throw error
        }

        do {
            let response = try await client.request("account/read", params: .object(["refreshToken": .bool(false)]))
            guard response["account"]?["type"]?.stringValue == "chatgpt" else {
                throw CodexAppServerError.notAuthenticated
            }
            await client.stop()
            try persist(context: context, accountID: accountID)
        } catch {
            await client.stop()
            try? persist(context: context, accountID: accountID)
            throw error
        }
    }

    func openDesktop(accountID: UUID, allAccountIDs: [UUID]) async throws {
        await gate.acquire()
        do {
            try await openDesktopUnlocked(accountID: accountID, allAccountIDs: allAccountIDs)
            await gate.release()
        } catch {
            await gate.release()
            throw error
        }
    }

    private func openDesktopUnlocked(accountID: UUID, allAccountIDs: [UUID]) async throws {
        try CodexNativeHome.validateConfiguration()
        guard let appURL = await CodexDesktopLauncher.applicationURL() else {
            throw CodexAppServerError.appMissing
        }

        try await CodexDesktopLauncher.quitRunningApplications()
        let previousAuth = try? Data(contentsOf: CodexNativeHome.authURL)
        if let previousAuth,
           let previousExternalID = CodexCredentialVault.externalAccountID(from: previousAuth) {
            for knownID in allAccountIDs {
                guard let stored = try? CodexCredentialVault.load(accountID: knownID) else { continue }
                if CodexCredentialVault.externalAccountID(from: stored) == previousExternalID {
                    try CodexCredentialVault.save(previousAuth, accountID: knownID)
                    break
                }
            }
        }

        do {
            // 先用官方 app-server 验证并刷新目标凭据，然后再改动原生 auth.json。
            try await validateUnlocked(accountID: accountID)
            let targetAuth = try CodexCredentialVault.load(accountID: accountID)
            try FileManager.default.createDirectory(at: CodexNativeHome.url, withIntermediateDirectories: true)
            try CodexCredentialVault.atomicWrite(targetAuth, to: CodexNativeHome.authURL)
            try await CodexDesktopLauncher.launchApplication(at: appURL)

            // 启动后只校验原生凭据的账号 ID；桌面 Codex 从未被传入隔离目录。
            try await Task.sleep(for: .milliseconds(500))
            let active = try Data(contentsOf: CodexNativeHome.authURL)
            guard CodexCredentialVault.externalAccountID(from: active) == CodexCredentialVault.externalAccountID(from: targetAuth) else {
                throw CodexAppServerError.invalidResponse("启动后账号校验失败")
            }
        } catch {
            try? await CodexDesktopLauncher.quitRunningApplications()
            if let previousAuth {
                try? CodexCredentialVault.atomicWrite(previousAuth, to: CodexNativeHome.authURL)
                try? await CodexDesktopLauncher.launchApplication(at: appURL)
            }
            throw error
        }
    }

    private struct Context {
        let homeURL: URL
        let runtime: CodexRuntimeHome?
    }

    private func makeContext(accountID: UUID) throws -> Context {
        let credential = try CodexCredentialVault.load(accountID: accountID)
        if let native = try? Data(contentsOf: CodexNativeHome.authURL),
           CodexCredentialVault.externalAccountID(from: native) == CodexCredentialVault.externalAccountID(from: credential) {
            return Context(homeURL: CodexNativeHome.url, runtime: nil)
        }
        let runtime = try CodexRuntimeHome.create(authData: credential)
        return Context(homeURL: runtime.url, runtime: runtime)
    }

    private func persist(context: Context, accountID: UUID) throws {
        defer { context.runtime?.remove() }
        if let runtime = context.runtime {
            try runtime.persistCredential(accountID: accountID)
        } else {
            try CodexCredentialVault.save(Data(contentsOf: CodexNativeHome.authURL), accountID: accountID)
        }
    }
}

enum CodexAccountService {
    static func refresh(accountID: UUID) async throws -> CodexAccountResult {
        try await CodexAccountCoordinator.shared.refresh(accountID: accountID)
    }

    static func validate(accountID: UUID) async throws {
        try await CodexAccountCoordinator.shared.validate(accountID: accountID)
    }

    static func parse(account: JSONValue, limits: JSONValue, usage: JSONValue) -> CodexAccountResult {
        let accountValue = account["account"]
        let snapshot = limits["rateLimits"]
        let primary = parseLimit(snapshot?["primary"], fallbackName: "Codex 主额度")
        let secondary = parseLimit(snapshot?["secondary"], fallbackName: "Codex 次级额度")
        let summary = usage["summary"]
        let dailyUsage = (usage["dailyUsageBuckets"]?.arrayValue ?? []).compactMap { bucket -> (Date, Int)? in
            guard let text = bucket["startDate"]?.stringValue,
                  let date = dayFormatter.date(from: text),
                  let tokens = bucket["tokens"]?.intValue else { return nil }
            return (Calendar.current.startOfDay(for: date), tokens)
        }
        return CodexAccountResult(
            email: accountValue?["email"]?.stringValue,
            planType: accountValue?["planType"]?.stringValue ?? snapshot?["planType"]?.stringValue ?? "unknown",
            primaryLimit: primary,
            secondaryLimit: secondary,
            lifetimeTokens: summary?["lifetimeTokens"]?.intValue,
            peakDailyTokens: summary?["peakDailyTokens"]?.intValue,
            currentStreakDays: summary?["currentStreakDays"]?.intValue,
            dailyUsage: dailyUsage
        )
    }

    private static func parseLimit(_ value: JSONValue?, fallbackName: String) -> CodexLimit? {
        guard let used = value?["usedPercent"]?.doubleValue else { return nil }
        let minutes = value?["windowDurationMins"]?.intValue
        return CodexLimit(
            name: limitName(minutes: minutes, fallback: fallbackName),
            usedPercent: used,
            resetsAt: value?["resetsAt"]?.doubleValue.map(Date.init(timeIntervalSince1970:)),
            windowMinutes: minutes
        )
    }

    private static func limitName(minutes: Int?, fallback: String) -> String {
        guard let minutes else { return fallback }
        switch minutes {
        case 300: return "Codex 5 小时额度"
        case 1_440: return "Codex 每日额度"
        case 10_080: return "Codex 周额度"
        case let value where value % 1_440 == 0: return "Codex \(value / 1_440) 天额度"
        case let value where value % 60 == 0: return "Codex \(value / 60) 小时额度"
        default: return fallback
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum CodexDesktopLauncher {
    static func open(accountID: UUID, allAccountIDs: [UUID]) async throws {
        try await CodexAccountCoordinator.shared.openDesktop(
            accountID: accountID,
            allAccountIDs: allAccountIDs
        )
    }

    @MainActor
    static func applicationURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
    }

    @MainActor
    static func quitRunningApplications() async throws {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
        for application in applications where !application.isTerminated {
            application.terminate()
        }
        let deadline = Date.now.addingTimeInterval(15)
        while NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
            .contains(where: { !$0.isTerminated }) {
            guard Date.now < deadline else { throw CodexAppServerError.codexDidNotQuit }
            try await Task.sleep(for: .milliseconds(150))
        }
    }

    @MainActor
    static func launchApplication(at appURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
