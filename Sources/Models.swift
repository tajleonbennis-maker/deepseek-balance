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
