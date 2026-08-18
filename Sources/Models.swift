import Foundation

// MARK: - 单个 API Key 配置
struct KeyConfig: Codable, Identifiable {
    var id: String
    var name: String
    var apiKey: String
    var enabled: Bool

    init(id: String = UUID().uuidString, name: String, apiKey: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.apiKey = apiKey
        self.enabled = enabled
    }

    /// 打码展示：sk-abc…xyz
    var maskedKey: String {
        guard apiKey.count > 10 else { return "sk-***" }
        return String(apiKey.prefix(6)) + "…" + String(apiKey.suffix(4))
    }
}

// MARK: - 全局配置
struct AppConfig: Codable {
    var keys: [KeyConfig] = []
    var refreshInterval: Double = 60          // 轮询间隔（秒）
    var lowBalanceAlert: Bool = true          // 低余额提醒开关
    var alertThreshold: Double = 10.0         // 提醒阈值（按各 key 本位币）
    var notifiedLowKeys: [String: Double] = [:] // keyId -> 上次提醒时的余额

    // 突发消耗告警
    var spikeAlert: Bool = true               // 单次轮询消耗超阈值告警
    var spikeThreshold: Double = 1.0          // 单次消耗 > ¥X 触发
    var notifiedSpikeKeys: [String: Double] = [:]

    // 消耗速率告警
    var rateAlert: Bool = true
    var rateThreshold: Double = 0.5           // 速率 > ¥X/分钟 触发
    var notifiedRateKeys: [String: Double] = [:]

    init() {}

    // 自定义解码：旧配置无新字段时使用默认值（向前兼容）
    private enum CodingKeys: String, CodingKey {
        case keys, refreshInterval, lowBalanceAlert, alertThreshold, notifiedLowKeys
        case spikeAlert, spikeThreshold, rateAlert, rateThreshold
        case notifiedSpikeKeys, notifiedRateKeys
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keys = (try? c.decode([KeyConfig].self, forKey: .keys)) ?? []
        refreshInterval = (try? c.decode(Double.self, forKey: .refreshInterval)) ?? 60
        lowBalanceAlert = (try? c.decode(Bool.self, forKey: .lowBalanceAlert)) ?? true
        alertThreshold = (try? c.decode(Double.self, forKey: .alertThreshold)) ?? 10.0
        notifiedLowKeys = (try? c.decode([String: Double].self, forKey: .notifiedLowKeys)) ?? [:]
        spikeAlert = (try? c.decode(Bool.self, forKey: .spikeAlert)) ?? true
        spikeThreshold = (try? c.decode(Double.self, forKey: .spikeThreshold)) ?? 1.0
        rateAlert = (try? c.decode(Bool.self, forKey: .rateAlert)) ?? true
        rateThreshold = (try? c.decode(Double.self, forKey: .rateThreshold)) ?? 0.5
        notifiedSpikeKeys = (try? c.decode([String: Double].self, forKey: .notifiedSpikeKeys)) ?? [:]
        notifiedRateKeys = (try? c.decode([String: Double].self, forKey: .notifiedRateKeys)) ?? [:]
    }
}

// MARK: - 每日余额快照（用于计算用量/消耗）
struct DayRecord: Codable {
    var day: String      // yyyy-MM-dd
    var keyId: String
    var open: Double     // 当天首次观测余额
    var close: Double    // 当天最近一次观测余额
}

// MARK: - 单次余额查询结果
struct BalanceResult {
    enum Status: Int {
        case ok = 0
        case invalidKey      // 401
        case rateLimited     // 429
        case networkError
        case serverError
    }

    var keyId: String
    var status: Status
    var isAvailable: Bool = false
    var currency: String = "CNY"
    var total: Double = 0
    var granted: Double = 0
    var toppedUp: Double = 0
    var timestamp: Date = Date()

    var statusText: String {
        switch status {
        case .ok:           return isAvailable ? "正常" : "余额不足"
        case .invalidKey:   return "密钥无效"
        case .rateLimited:  return "限流"
        case .networkError: return "网络错误"
        case .serverError:  return "服务异常"
        }
    }
}

// MARK: - 服务器配置
struct ServerConfig: Codable, Identifiable {
    var id: String
    var name: String
    var host: String        // IP 或 IP:port
    var username: String
    var password: String    // 本地明文存储，仅用于本机 SSH 采集
    var enabled: Bool

    init(id: String = UUID().uuidString, name: String, host: String,
         username: String, password: String, enabled: Bool = true) {
        self.id = id
        self.name = name
        self.host = host
        self.username = username
        self.password = password
        self.enabled = enabled
    }
}

// MARK: - 单次登录记录（登录审计）
struct LoginRecord: Codable {
    var user: String
    var fromIP: String
    var time: String        // 如 "08-16 11:54"
    var duration: String    // 如 "00:06"
}

// MARK: - 服务器健康状态（单次采集结果）
struct ServerStatus: Codable {
    var serverId: String
    var timestamp: Date
    var online: Bool
    var error: String?

    var memPercent: Double = 0      // 内存使用率 %
    var memUsedMB: Double = 0
    var memTotalMB: Double = 0
    var memAvailMB: Double = 0
    var swapPercent: Double = 0

    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0

    var diskPercent: Double = 0
    var diskUsedGB: Double = 0
    var diskTotalGB: Double = 0

    var topProcesses: [String] = []
    var logins: [LoginRecord] = []
}

// MARK: - 告警历史记录（可追溯）
struct AlertRecord: Codable, Identifiable {
    var id: String
    var timestamp: Date
    var category: String   // 用量告警 / 余额提醒 / 服务器告警
    var subject: String    // 账号名 / 服务器名
    var body: String

    init(id: String = UUID().uuidString, timestamp: Date = Date(),
         category: String, subject: String, body: String) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.subject = subject
        self.body = body
    }
}

// MARK: - 服务器状态历史（精简快照，按次采集追加）
struct ServerHistoryEntry: Codable {
    var serverId: String
    var timestamp: Date
    var online: Bool
    var memPercent: Double
    var diskPercent: Double
    var swapPercent: Double
    var load1: Double
}
