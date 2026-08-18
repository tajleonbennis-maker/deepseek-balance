import Foundation

/// 本地存储：config.json（Key 配置）+ records.json（每日余额快照）
/// 全部数据保存在 ~/Library/Application Support/DeepSeekBalance/，不上传任何地方
final class Store {

    static let shared = Store()

    private let dir: URL
    private let configURL: URL
    private let recordsURL: URL

    var config = AppConfig()
    private(set) var records: [DayRecord] = []
    private var latestResults: [String: BalanceResult] = [:] // keyId -> 最近一次结果
    private var lastSeen: [String: (total: Double, time: Date)] = [:] // 上一轮观测余额+时间，用于算 delta/dt

    private init() {
        dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DeepSeekBalance", isDirectory: true)
        configURL = dir.appendingPathComponent("config.json")
        recordsURL = dir.appendingPathComponent("records.json")
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
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(config) { try? d.write(to: configURL) }
        if let d = try? enc.encode(records) { try? d.write(to: recordsURL) }
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
