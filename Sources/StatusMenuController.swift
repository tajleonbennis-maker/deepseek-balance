import AppKit
import UserNotifications

/// 菜单栏控制器：右上角常驻，定时轮询所有 SK，实时刷新余额显示
final class StatusMenuController: NSObject, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?
    private var serverTimer: Timer?
    private var isRefreshing = false
    private var lastRefreshTime: Date?
    private var lastTitle = ""
    private var pendingRefresh: DispatchWorkItem?
    private var notifiedServerAlerts: Set<String> = []

    private var settingsWindow: SettingsWindowController?
    private var serverWindow: ServerWindowController?

    override init() {
        super.init()
        setupStatusItem()
        startTimer()
        refreshAll()
        startServerTimer()
        checkServers()
    }

    // MARK: - 状态栏

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let img = NSImage(systemSymbolName: "dollarsign.circle.fill", accessibilityDescription: "DeepSeek 余额")
        button.image = img?.withSymbolConfiguration(cfg)
        button.imagePosition = .imageLeading
        button.title = "…"
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        statusItem.menu = buildMenu()
        statusItem.menu?.delegate = self
    }

    /// 汇总余额显示到菜单栏：CNY 优先，USD 追加
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let sum = Store.shared.sumBalances()
        var parts: [String] = []
        if sum.cny > 0 { parts.append(StatusMenuController.fmt(sum.cny, "CNY")) }
        if sum.usd > 0 { parts.append(StatusMenuController.fmt(sum.usd, "USD")) }
        if parts.isEmpty {
            // 一个成功结果都没有：区分「未配置」和「全部失败」
            if Store.shared.config.keys.isEmpty {
                button.title = "未配置"
            } else {
                button.title = "--"
            }
        } else {
            button.title = parts.joined(separator: " · ")
        }
        lastTitle = button.title
    }

    // MARK: - 轮询调度

    func startTimer() {
        timer?.invalidate()
        let interval = max(15, Store.shared.config.refreshInterval)
        let t = Timer(timeInterval: interval, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func timerFired() {
        refreshAll()
    }

    /// 打开菜单时，若距上次刷新超过 10 秒则顺手刷新（保持「实时」感）
    func menuWillOpen(_ menu: NSMenu) {
        if let last = lastRefreshTime, Date().timeIntervalSince(last) < 10 { return }
        refreshAll(rebuildMenu: false)
    }

    /// 刷新所有启用的 key
    func refreshAll(rebuildMenu: Bool = true) {
        guard !isRefreshing else { return }
        let keys = Store.shared.config.keys.filter { $0.enabled }
        guard !keys.isEmpty else {
            lastRefreshTime = Date()
            updateStatusItem()
            statusItem.menu = buildMenu()
            return
        }

        isRefreshing = true
        lastRefreshTime = Date()
        let group = DispatchGroup()
        let lock = NSLock()

        for key in keys {
            group.enter()
            BalanceFetcher.fetch(key) { [weak self] result in
                lock.lock()
                let (delta, dt) = Store.shared.record(result: result)
                lock.unlock()
                self?.checkSpike(key: key, result: result, delta: delta, dt: dt)
                self?.checkLowBalance(key: key, result: result)
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isRefreshing = false
            self.updateStatusItem()
            if rebuildMenu {
                self.statusItem.menu = self.buildMenu()
            } else {
                self.statusItem.menu = self.buildMenu()
            }
        }
    }

    // MARK: - 低余额提醒

    private func checkLowBalance(key: KeyConfig, result: BalanceResult) {
        let cfg = Store.shared.config
        guard cfg.lowBalanceAlert,
              result.status == .ok,
              !result.isAvailable || result.total < cfg.alertThreshold
        else {
            // 余额回到阈值以上，重置提醒状态
            if cfg.notifiedLowKeys[key.id] != nil {
                Store.shared.config.notifiedLowKeys.removeValue(forKey: key.id)
                Store.shared.save()
            }
            return
        }
        guard cfg.notifiedLowKeys[key.id] == nil else { return }
        Store.shared.config.notifiedLowKeys[key.id] = result.total
        Store.shared.save()

        let reason = !result.isAvailable ? "余额不足以继续调用 API" : "已低于 ¥\(cfg.alertThreshold) 阈值"
        notify(title: "DeepSeek 余额提醒 · \(key.name)", body: "当前余额 \(StatusMenuController.fmt(result.total, result.currency))，\(reason)", category: "余额提醒", subject: key.name)
    }

    private func notify(title: String, body: String, category: String = "用量告警", subject: String = "") {
        // 1) 写入历史（可追溯）
        Store.shared.record(alert: AlertRecord(category: category, subject: subject.isEmpty ? title : subject, body: body))
        // 2) 发系统通知
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                let send = { () in
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    content.sound = .default
                    let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    center.add(req)
                }
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    send()
                case .notDetermined:
                    // 首次使用：先请求授权，同意后再发
                    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                        if granted { DispatchQueue.main.async { send() } }
                    }
                case .denied:
                    break // 系统设置中已关闭，设置窗口可查看并引导开启
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - 突发消耗与速率告警

    private func checkSpike(key: KeyConfig, result: BalanceResult, delta: Double, dt: TimeInterval) {
        guard result.status == .ok, dt > 0 else { return }
        let cfg = Store.shared.config
        var messages: [String] = []
        var dirty = false

        // 单次尖刺：本次轮询消耗金额超阈值
        if cfg.spikeAlert && delta >= cfg.spikeThreshold {
            let last = cfg.notifiedSpikeKeys[key.id]
            // 抑制：上次告警后余额下降不达 spikeThreshold 的一半就不再骚扰
            let cooldown = cfg.spikeThreshold * 0.5
            if last == nil || (last! - result.total) >= cooldown {
                Store.shared.config.notifiedSpikeKeys[key.id] = result.total
                dirty = true
                let minutes = Int(dt / 60); let secs = Int(dt.truncatingRemainder(dividingBy: 60))
                let durStr = minutes > 0 ? "\(minutes)分\(secs)秒" : "\(secs)秒"
                messages.append("⚡ 单次消耗 \(StatusMenuController.fmt(delta, result.currency))（间隔 \(durStr)）")
            }
        } else if delta < 0 {
            // 充值 / 入账后清掉抑制，下次再消耗可再次告警
            if cfg.notifiedSpikeKeys[key.id] != nil {
                Store.shared.config.notifiedSpikeKeys.removeValue(forKey: key.id)
                dirty = true
            }
        }

        // 速率告警：每分钟消耗速率超阈值
        if cfg.rateAlert && delta > 0 {
            let perMin = delta / dt * 60
            if perMin >= cfg.rateThreshold {
                let last = cfg.notifiedRateKeys[key.id]
                let cooldown = cfg.rateThreshold * 0.3   // 元
                if last == nil || (last! - result.total) >= cooldown {
                    Store.shared.config.notifiedRateKeys[key.id] = result.total
                    dirty = true
                    messages.append("📈 消耗速率 \(StatusMenuController.fmt(perMin, result.currency))/分钟")
                }
            }
        }

        if dirty { Store.shared.save() }
        for body in messages {
            notify(title: "DeepSeek 用量告警 · \(key.name)", body: body, category: "用量告警", subject: key.name)
        }
    }

    // MARK: - 菜单构建

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 头部
        let header = NSMenuItem(title: "DeepSeek 余额监控", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let keys = Store.shared.config.keys
        if keys.isEmpty {
            let hint = NSMenuItem(title: "尚未添加 API Key —— 点下方「设置…」添加", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        } else {
            for key in keys {
                addKeyItems(key: key, to: menu)
            }
        }

        menu.addItem(.separator())

        // 用量汇总
        addUsageSummary(to: menu)

        menu.addItem(.separator())

        // 服务器状态
        addServerSection(to: menu)

        menu.addItem(.separator())

        // 状态行
        let lastText = lastRefreshTime.map { "上次更新 \(Self.timeString($0))" } ?? "尚未刷新"
        let intervalText = "自动刷新 \(Int(max(15, Store.shared.config.refreshInterval)))s"
        let statusLine = NSMenuItem(title: "\(lastText) · \(intervalText) · \(isRefreshing ? "刷新中…" : "就绪")", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        // 操作
        let refresh = NSMenuItem(title: "立即刷新", action: #selector(refreshAction), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let serverMgr = NSMenuItem(title: "服务器管理…", action: #selector(openServerManager), keyEquivalent: "s")
        serverMgr.target = self
        menu.addItem(serverMgr)

        let serverChat = NSMenuItem(title: "服务器助手…（AI 对话）", action: #selector(openServerChat), keyEquivalent: "c")
        serverChat.target = self
        menu.addItem(serverChat)

        let history = NSMenuItem(title: "历史记录…", action: #selector(openHistory), keyEquivalent: "h")
        history.target = self
        menu.addItem(history)

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func addKeyItems(key: KeyConfig, to menu: NSMenu) {
        let res = Store.shared.result(for: key.id)

        // 主行：名称 + 余额 + 状态标记
        let line: String
        if let r = res, r.status == .ok {
            let mark = r.isAvailable ? "●" : "▲"
            line = "\(key.name)  \(StatusMenuController.fmt(r.total, r.currency)) \(mark)"
        } else if let r = res {
            line = "\(key.name)  \(r.statusText) ⚠"
        } else {
            line = "\(key.name)  查询中…"
        }
        let main = NSMenuItem(title: line, action: nil, keyEquivalent: "")
        main.isEnabled = false
        menu.addItem(main)

        // 明细行：充值/赠送 + 今日消耗
        if let r = res, r.status == .ok {
            let parts = [
                "充值 \(StatusMenuController.fmt(r.toppedUp, r.currency))",
                "赠送 \(StatusMenuController.fmt(r.granted, r.currency))",
            ]
            var sub = parts.joined(separator: " · ")
            if let today = Store.shared.consumptionToday(for: key.id) {
                sub += " · 今日 \(StatusMenuController.fmtSigned(today, r.currency))"
            }
            let item = NSMenuItem(title: "    " + sub + "    ", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let r = res {
            let item = NSMenuItem(title: "    \(r.statusText) · \(key.maskedKey)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    private func addUsageSummary(to menu: NSMenu) {
        let keys = Store.shared.config.keys.filter { $0.enabled }
        var today: (sum: Double, count: Int) = (0, 0)
        var week: (sum: Double, count: Int) = (0, 0)

        for key in keys {
            if let t = Store.shared.consumptionToday(for: key.id) {
                today.sum += t
                today.count += 1
            }
            if let w = Store.shared.consumption(for: key.id, daysAgo: 7) {
                week.sum += w
                week.count += 1
            }
        }

        var lines: [String] = []
        if today.count > 0 {
            lines.append("今日消耗  \(StatusMenuController.fmtSigned(today.sum, "CNY"))")
        }
        if week.count > 0 {
            lines.append("近7天消耗 \(StatusMenuController.fmtSigned(week.sum, "CNY"))")
        }
        if lines.isEmpty {
            let item = NSMenuItem(title: "用量统计：运行一段时间后自动生成", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            for l in lines {
                let item = NSMenuItem(title: l, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
    }

    // MARK: - 服务器监控

    private func addServerSection(to menu: NSMenu) {
        let servers = Store.shared.servers
        if servers.isEmpty {
            let item = NSMenuItem(title: "服务器监控：点下方「服务器管理…」添加", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }
        let header = NSMenuItem(title: "服务器状态（每小时更新）", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // 健康汇总行：在线 / 告警一眼可见
        let online = servers.filter {
            guard let st = Store.shared.serverStatus(for: $0.id) else { return false }
            return st.online
        }.count
        let alerting = servers.filter {
            guard let st = Store.shared.serverStatus(for: $0.id), st.online else { return false }
            return st.memPercent >= 90 || st.diskPercent >= 85
        }.count
        if alerting > 0 {
            let summary = NSMenuItem(title: "⚠️ \(alerting) 台告警 · \(online) 台在线（共 \(servers.count) 台）", action: nil, keyEquivalent: "")
            summary.isEnabled = false
            menu.addItem(summary)
        } else {
            let summary = NSMenuItem(title: "✅ \(online) 台在线 · 全部正常（共 \(servers.count) 台）", action: nil, keyEquivalent: "")
            summary.isEnabled = false
            menu.addItem(summary)
        }

        for server in servers {
            let st = Store.shared.serverStatus(for: server.id)
            let title: String
            if let st = st, st.online {
                let hist = Store.shared.serverHistory
                    .filter { $0.serverId == server.id }
                    .suffix(2)
                    .map { $0 }
                var memArrow = ""
                var diskArrow = ""
                if hist.count >= 2 {
                    let memDiff = hist[1].memPercent - hist[0].memPercent
                    let diskDiff = hist[1].diskPercent - hist[0].diskPercent
                    memArrow = memDiff > 1 ? "↑" : (memDiff < -1 ? "↓" : "")
                    diskArrow = diskDiff > 1 ? "↑" : (diskDiff < -1 ? "↓" : "")
                }
                let dot = (st.memPercent >= 90 || st.diskPercent >= 85) ? "🔴" : "🟢"
                title = "\(dot) \(server.name)  内存 \(Int(st.memPercent))%\(memArrow)  磁盘 \(Int(st.diskPercent))%\(diskArrow)  负载 \(String(format: "%.2f", st.load1))"
            } else if let st = st {
                title = "🔴 \(server.name)  \(st.error ?? "采集失败")"
            } else {
                title = "⚪ \(server.name)  未采集"
            }
            let item = NSMenuItem(title: title, action: #selector(openServerDetail(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = server.id
            menu.addItem(item)
        }
    }

    func startServerTimer() {
        serverTimer?.invalidate()
        let t = Timer(timeInterval: 3600, target: self, selector: #selector(serverTimerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        serverTimer = t
    }

    @objc private func serverTimerFired() {
        checkServers()
    }

    func checkServers() {
        let servers = Store.shared.servers.filter { $0.enabled }
        guard !servers.isEmpty else { return }
        for server in servers {
            ServerMonitor.shared.collect(server: server) { [weak self] status in
                DispatchQueue.main.async {
                    Store.shared.record(serverStatus: status)
                    self?.checkServerAlert(server: server, status: status)
                    self?.statusItem.menu = self?.buildMenu()
                }
            }
        }
    }

    private func checkServerAlert(server: ServerConfig, status: ServerStatus) {
        guard status.online else { return }
        var alerts: [String] = []
        if status.memPercent >= 90 {
            let key = "\(server.id):mem"
            if !notifiedServerAlerts.contains(key) {
                notifiedServerAlerts.insert(key)
                alerts.append("内存使用率 \(Int(status.memPercent))%（可用 \(Int(status.memAvailMB))MB）")
            }
        } else {
            notifiedServerAlerts.remove("\(server.id):mem")
        }
        if status.diskPercent >= 85 {
            let key = "\(server.id):disk"
            if !notifiedServerAlerts.contains(key) {
                notifiedServerAlerts.insert(key)
                alerts.append("磁盘使用率 \(Int(status.diskPercent))%（剩余 \(max(0, status.diskTotalGB - status.diskUsedGB))GB）")
            }
        } else {
            notifiedServerAlerts.remove("\(server.id):disk")
        }
        for a in alerts {
            notify(title: "服务器告警 · \(server.name)", body: a, category: "服务器告警", subject: server.name)
        }
    }

    @objc private func openServerManager() {
        if serverWindow == nil {
            serverWindow = ServerWindowController()
        }
        serverWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 菜单里点某台服务器 → 弹单台详情窗
    @objc private func openServerDetail(_ sender: NSMenuItem) {
        guard let sid = sender.representedObject as? String else { return }
        ServerQuickViewController.show(serverId: sid)
    }

    @objc private func openHistory() {
        HistoryWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openServerChat() {
        ServerChatWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Actions

    @objc private func refreshAction() {
        refreshAll()
    }

    @objc private func openSettingsAction() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(onChange: { [weak self] in
                self?.startTimer()
                self?.refreshAll()
            })
        }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitAction() {
        Store.shared.save()
        NSApp.terminate(nil)
    }

    // MARK: - 工具

    static func fmt(_ v: Double, _ currency: String) -> String {
        let symbol = currency.uppercased() == "USD" ? "$" : "¥"
        if v >= 100 { return symbol + String(format: "%.0f", v) }
        if v >= 1 { return symbol + String(format: "%.2f", v) }
        return symbol + String(format: "%.3f", v)
    }

    static func fmtSigned(_ v: Double, _ currency: String) -> String {
        if v > 0 { return "-" + fmt(v, currency) }
        if v < 0 { return "+" + fmt(-v, currency) }
        return "0"
    }

    private static func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
