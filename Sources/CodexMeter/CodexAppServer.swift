import AppKit
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
    case historyMigrationFailed(String)

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
        case .historyMigrationFailed(let message):
            return "合并 Codex 对话历史失败：\(message)"
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

enum CodexAccountHome {
    struct LegacyMigration {
        let sourceAuth: URL
        let destinationAuth: URL
    }

    static func url(for accountID: UUID, create: Bool = true) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let home = support
            .appendingPathComponent("CodexMonitor/Accounts/\(accountID.uuidString)/CodexHome", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }
        return home
    }

    static func delete(accountID: UUID) {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) else { return }
        try? FileManager.default.removeItem(
            at: support.appendingPathComponent("CodexMonitor/Accounts/\(accountID.uuidString)")
        )
    }

    static func prepareLegacyMigration(accountID: UUID) throws -> LegacyMigration? {
        let home = try url(for: accountID)
        let destination = home.appendingPathComponent("auth.json")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return nil }

        let accountRoot = home.deletingLastPathComponent()
        let legacyDirectory = accountRoot.appendingPathComponent("Quotio/auth", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil),
              let source = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first(where: {
                  $0.lastPathComponent.hasPrefix("codex-") && $0.pathExtension == "json"
              }) else {
            return nil
        }

        let data = try Data(contentsOf: source)
        guard let legacy = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = legacy["id_token"] as? String,
              let accessToken = legacy["access_token"] as? String,
              let refreshToken = legacy["refresh_token"] as? String,
              let accountID = legacy["account_id"] as? String else {
            throw CodexAppServerError.invalidResponse("旧账号凭据不完整")
        }

        let auth: [String: Any] = [
            "OPENAI_API_KEY": NSNull(),
            "auth_mode": "chatgpt",
            "tokens": [
                "id_token": idToken,
                "access_token": accessToken,
                "refresh_token": refreshToken,
                "account_id": accountID
            ],
            "last_refresh": (legacy["last_refresh"] as? String) ?? ISO8601DateFormatter().string(from: .now)
        ]
        let output = try JSONSerialization.data(withJSONObject: auth, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return LegacyMigration(sourceAuth: source, destinationAuth: destination)
    }

    static func commit(_ migration: LegacyMigration) throws {
        try FileManager.default.removeItem(at: migration.sourceAuth)
    }

    static func rollback(_ migration: LegacyMigration) {
        try? FileManager.default.removeItem(at: migration.destinationAuth)
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

enum CodexConversationStore {
    static func sharedHomeURL() -> URL {
        if let configured = ProcessInfo.processInfo.environment["CODEX_SQLITE_HOME"], !configured.isEmpty {
            return URL(fileURLWithPath: configured).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    static func mergeAccountHistoryIfNeeded(accountHome: URL, sharedHome: URL) async throws {
        do {
            try await Task.detached(priority: .userInitiated) {
                try mergeSynchronously(accountHome: accountHome, sharedHome: sharedHome)
            }.value
        } catch let error as CodexAppServerError {
            throw error
        } catch {
            throw CodexAppServerError.historyMigrationFailed(error.localizedDescription)
        }
    }

    private static func mergeSynchronously(accountHome: URL, sharedHome: URL) throws {
        let manager = FileManager.default
        let source = accountHome.appendingPathComponent("state_5.sqlite")
        let destination = sharedHome.appendingPathComponent("state_5.sqlite")
        guard source.standardizedFileURL != destination.standardizedFileURL,
              manager.fileExists(atPath: source.path),
              manager.fileExists(atPath: destination.path) else { return }

        let sourcePath = sqlQuoted(source.path)
        let countSQL = """
        ATTACH DATABASE '\(sourcePath)' AS account_state;
        SELECT COUNT(*)
        FROM account_state.threads AS source
        WHERE NOT EXISTS (SELECT 1 FROM main.threads AS target WHERE target.id = source.id);
        """
        let countText = try runSQLite(database: destination, command: countSQL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let missingCount = Int(countText), missingCount > 0 else { return }

        let backupDirectory = accountHome.appendingPathComponent("migration-backups", isDirectory: true)
        try manager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backupDirectory.path)
        let stamp = backupFormatter.string(from: .now)
        let backup = backupDirectory.appendingPathComponent("shared-state-before-merge-\(stamp).sqlite")
        _ = try runSQLite(database: destination, command: ".backup '\(sqlQuoted(backup.path))'")
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)

        let mergeSQL = """
        PRAGMA busy_timeout = 10000;
        ATTACH DATABASE '\(sourcePath)' AS account_state;
        BEGIN IMMEDIATE;
        INSERT OR IGNORE INTO main.threads SELECT * FROM account_state.threads;
        INSERT OR IGNORE INTO main.thread_dynamic_tools SELECT * FROM account_state.thread_dynamic_tools;
        INSERT OR IGNORE INTO main.thread_spawn_edges SELECT * FROM account_state.thread_spawn_edges;
        INSERT OR IGNORE INTO main.agent_jobs SELECT * FROM account_state.agent_jobs;
        INSERT OR IGNORE INTO main.agent_job_items SELECT * FROM account_state.agent_job_items;
        COMMIT;
        """
        _ = try runSQLite(database: destination, command: mergeSQL)
    }

    private static func runSQLite(database: URL, command: String) throws -> String {
        let executable = URL(fileURLWithPath: "/usr/bin/sqlite3")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CodexAppServerError.historyMigrationFailed("系统缺少 sqlite3")
        }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = [database.path, command]
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() }
        catch { throw CodexAppServerError.historyMigrationFailed(error.localizedDescription) }
        process.waitUntilExit()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexAppServerError.historyMigrationFailed(message?.isEmpty == false ? message! : "sqlite3 返回 \(process.terminationStatus)")
        }
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    private static func sqlQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static let backupFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
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

    static func start(accountID: UUID) async throws -> CodexAppServerClient {
        let client = CodexAppServerClient(homeURL: try CodexAccountHome.url(for: accountID))
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
        if process.isRunning { process.terminate() }
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
    private var activeURL: URL?
    private var loginID: String?

    init(accountID: UUID) {
        self.accountID = accountID
    }

    func start() async throws {
        guard client == nil else { return }
        client = try await CodexAppServerClient.start(accountID: accountID)
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
        guard let client else { return }
        self.client = nil
        await client.stop()
    }
}

enum CodexAccountService {
    static func refresh(accountID: UUID) async throws -> CodexAccountResult {
        let migration = try CodexAccountHome.prepareLegacyMigration(accountID: accountID)
        var migrationCommitted = false
        let client: CodexAppServerClient
        do {
            client = try await CodexAppServerClient.start(accountID: accountID)
        } catch {
            if let migration { CodexAccountHome.rollback(migration) }
            throw error
        }

        do {
            let account = try await client.request("account/read", params: .object(["refreshToken": .bool(false)]))
            guard account["account"]?["type"]?.stringValue == "chatgpt" else {
                throw CodexAppServerError.notAuthenticated
            }
            if let migration {
                do {
                    try CodexAccountHome.commit(migration)
                } catch {
                    CodexAccountHome.rollback(migration)
                    throw error
                }
                migrationCommitted = true
            }

            async let limitsRequest = client.request("account/rateLimits/read")
            async let usageRequest = client.request("account/usage/read")
            let (limits, usage) = try await (limitsRequest, usageRequest)
            await client.stop()
            return parse(account: account, limits: limits, usage: usage)
        } catch {
            await client.stop()
            if let migration, !migrationCommitted { CodexAccountHome.rollback(migration) }
            throw error
        }
    }

    static func validate(accountID: UUID) async throws {
        let migration = try CodexAccountHome.prepareLegacyMigration(accountID: accountID)
        let client: CodexAppServerClient
        do {
            client = try await CodexAppServerClient.start(accountID: accountID)
        } catch {
            if let migration { CodexAccountHome.rollback(migration) }
            throw error
        }
        do {
            let response = try await client.request("account/read", params: .object(["refreshToken": .bool(false)]))
            guard response["account"]?["type"]?.stringValue == "chatgpt" else {
                throw CodexAppServerError.notAuthenticated
            }
            if let migration {
                do {
                    try CodexAccountHome.commit(migration)
                } catch {
                    CodexAccountHome.rollback(migration)
                    throw error
                }
            }
            await client.stop()
        } catch {
            await client.stop()
            if let migration { CodexAccountHome.rollback(migration) }
            throw error
        }
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
    @MainActor
    static func open(accountID: UUID) async throws {
        try await CodexAccountService.validate(accountID: accountID)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") else {
            throw CodexAppServerError.appMissing
        }
        let home = try CodexAccountHome.url(for: accountID)
        let sharedHome = CodexConversationStore.sharedHomeURL()
        try await CodexConversationStore.mergeAccountHistoryIfNeeded(accountHome: home, sharedHome: sharedHome)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        configuration.environment = [
            "CODEX_HOME": home.path,
            "CODEX_SQLITE_HOME": sharedHome.path
        ]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}
