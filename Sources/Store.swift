import Foundation

/// 本地存储：config.json（Key 配置）+ records.json（每日余额快照）
/// 全部数据保存在 ~/Library/Application Support/DeepSeekBalance/，不上传任何地方
final class Store {

    static let shared = Store()

    private let dir: URL
    private let configURL: URL
    private let recordsURL: URL
    private let serversURL: URL
    private let serverStatusURL: URL
    private let alertsURL: URL
    private let serverHistoryURL: URL
    private let chatLogsURL: URL

    var config = AppConfig()
    private(set) var records: [DayRecord] = []
    private(set) var servers: [ServerConfig] = []
    private(set) var serverStatuses: [String: ServerStatus] = [:] // serverId -> 最近采集结果
    private(set) var alerts: [AlertRecord] = []
    private(set) var serverHistory: [ServerHistoryEntry] = []
    private(set) var chatLogs: [ChatLog] = []
    private var latestResults: [String: BalanceResult] = [:] // keyId -> 最近一次结果
    private var lastSeen: [String: (total: Double, time: Date)] = [:] // 上一轮观测余额+时间，用于算 delta/dt

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepSeekBalance", isDirectory: true)
        configURL = dir.appendingPathComponent("config.json")
        recordsURL = dir.appendingPathComponent("records.json")
        serversURL = dir.appendingPathComponent("servers.json")
        serverStatusURL = dir.appendingPathComponent("server_status.json")
        alertsURL = dir.appendingPathComponent("alerts.json")
        serverHistoryURL = dir.appendingPathComponent("server_history.json")
        chatLogsURL = dir.appendingPathComponent("chat_logs.json")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var dataDirectory: URL { dir }

    // MARK: - 读写

    func load() {
        if let d = try? Data(contentsOf: configURL),
           let c = try? JSONDecoder().decode(AppConfig.self, from: d) {
            config = c
        }
        if let d = try? Data(contentsOf: recordsURL),
           let r = try? JSONDecoder().decode([DayRecord].self, from: d) {
            records = r
        }
        if let d = try? Data(contentsOf: serversURL),
           let s = try? JSONDecoder().decode([ServerConfig].self, from: d) {
            servers = s
        }
        if let d = try? Data(contentsOf: serverStatusURL),
           let st = try? JSONDecoder().decode([String: ServerStatus].self, from: d) {
            serverStatuses = st
        }
        if let d = try? Data(contentsOf: alertsURL),
           let a = try? JSONDecoder().decode([AlertRecord].self, from: d) {
            alerts = a
        }
        if let d = try? Data(contentsOf: serverHistoryURL),
           let h = try? JSONDecoder().decode([ServerHistoryEntry].self, from: d) {
            serverHistory = h
        }
        if let d = try? Data(contentsOf: chatLogsURL),
           let cl = try? JSONDecoder().decode([ChatLog].self, from: d) {
            chatLogs = cl
        }
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(config) { try? d.write(to: configURL) }
        if let d = try? enc.encode(records) { try? d.write(to: recordsURL) }
        if let d = try? enc.encode(servers) { try? d.write(to: serversURL) }
        if let d = try? enc.encode(serverStatuses) { try? d.write(to: serverStatusURL) }
        if let d = try? enc.encode(alerts) { try? d.write(to: alertsURL) }
        if let d = try? enc.encode(serverHistory) { try? d.write(to: serverHistoryURL) }
        if let d = try? enc.encode(chatLogs) { try? d.write(to: chatLogsURL) }
    }

    // MARK: - 服务器管理

    func upsertServer(_ server: ServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server
        } else {
            servers.append(server)
        }
        save()
    }

    func removeServer(id: String) {
        servers.removeAll { $0.id == id }
        serverStatuses.removeValue(forKey: id)
        save()
    }

    func record(serverStatus: ServerStatus) {
        serverStatuses[serverStatus.serverId] = serverStatus
        // 追加历史快照（精简），保留 7 天
        serverHistory.append(ServerHistoryEntry(
            serverId: serverStatus.serverId,
            timestamp: serverStatus.timestamp,
            online: serverStatus.online,
            memPercent: serverStatus.memPercent,
            diskPercent: serverStatus.diskPercent,
            swapPercent: serverStatus.swapPercent,
            load1: serverStatus.load1))
        let cutoff = Date().addingTimeInterval(-7 * 86400)
        serverHistory.removeAll { $0.timestamp < cutoff }
        if serverHistory.count > 2000 { serverHistory.removeFirst(serverHistory.count - 2000) }
        save()
    }

    func serverStatus(for id: String) -> ServerStatus? {
        serverStatuses[id]
    }

    // MARK: - 历史记录

    /// 记录一条告警历史（保留 90 天）
    func record(alert: AlertRecord) {
        alerts.append(alert)
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        alerts.removeAll { $0.timestamp < cutoff }
        if alerts.count > 5000 { alerts.removeFirst(alerts.count - 5000) }
        save()
    }

    /// 更新/追加一次 AI 助手会话日志（保留 30 天）
    func upsertChatLog(_ log: ChatLog) {
        if let idx = chatLogs.firstIndex(where: { $0.id == log.id }) {
            chatLogs[idx] = log
        } else {
            chatLogs.append(log)
        }
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        chatLogs.removeAll { $0.timestamp < cutoff }
        if chatLogs.count > 500 { chatLogs.removeFirst(chatLogs.count - 500) }
        save()
    }

    // MARK: - 快照与用量

    /// 记录一次成功的余额观测：当天只保留一条记录（open=首次, close=最新）
    /// 返回 (delta, dt) — delta = 上次余额 - 本次余额（正值=消耗），dt = 与上次观测的时间间隔（秒）
    func record(result: BalanceResult) -> (delta: Double, dt: TimeInterval) {
        var delta: Double = 0
        var dt: TimeInterval = 0
        if let prev = lastSeen[result.keyId] {
            delta = prev.total - result.total
            dt = result.timestamp.timeIntervalSince(prev.time)
        }
        lastSeen[result.keyId] = (result.total, result.timestamp)

        latestResults[result.keyId] = result
        guard result.status == .ok else { return (delta, dt) }

        let day = Self.dayString(result.timestamp)
        if let idx = records.firstIndex(where: { $0.day == day && $0.keyId == result.keyId }) {
            records[idx].close = result.total
        } else {
            records.append(DayRecord(day: day, keyId: result.keyId, open: result.total, close: result.total))
        }
        pruneRecords()
        save()
        return (delta, dt)
    }

    /// 保留最近 60 天快照
    private func pruneRecords() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
        let cutoffStr = Self.dayString(cutoff)
        records.removeAll { $0.day < cutoffStr }
    }

    func result(for keyId: String) -> BalanceResult? {
        latestResults[keyId]
    }

    /// 自 N 天前（当天起算）以来的消耗金额 = 基线余额 - 当前余额
    /// 正数=消耗，负数=充值/入账
    func consumption(for keyId: String, daysAgo: Int) -> Double? {
        guard let cur = latestResults[keyId], cur.status == .ok else { return nil }
        let baseDay = Self.dayString(Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!)
        let recs = records
            .filter { $0.keyId == keyId && $0.day >= baseDay }
            .sorted { $0.day < $1.day }
        guard let first = recs.first else { return nil }
        return first.open - cur.total
    }

    func consumptionToday(for keyId: String) -> Double? {
        consumption(for: keyId, daysAgo: 0)
    }

    /// 汇总所有 key 的最新余额，按货币分组
    func sumBalances() -> (cny: Double, usd: Double, count: Int) {
        var cny = 0.0, usd = 0.0
        var count = 0
        for key in config.keys where key.enabled {
            guard let r = latestResults[key.id], r.status == .ok else { continue }
            if r.currency.uppercased() == "USD" { usd += r.total } else { cny += r.total }
            count += 1
        }
        return (cny, usd, count)
    }

    static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }
}
