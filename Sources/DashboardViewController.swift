import AppKit

/// 紧凑版总览视图（用于菜单栏 NSPopover 一展开就看全部；也可被 DashboardWindowController 复用）
/// 固定 320 宽，高度按内容动态
final class DashboardViewController: NSViewController {

    private let cardW: CGFloat = 320

    // 内容容器
    private let content = NSView()

    // 头部
    private let titleLabel = NSTextField(labelWithString: "总览")
    private let timeLabel = NSTextField(labelWithString: "")
    private let refreshBtn = NSButton(title: "刷新", target: nil, action: nil)

    // 缓存内容高度（popover 调整用）
    private(set) var contentHeight: CGFloat = 560

    override func loadView() {
        // 直接构造 view，固定 320 宽、高度动态
        view = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: 600))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.subviews = []
        view.addSubview(content)
        content.frame = NSRect(x: 0, y: 0, width: cardW, height: 600)
        rebuild()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        rebuild()
    }

    // MARK: - 重建

    func rebuild() {
        content.subviews = []

        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        timeLabel.stringValue = f.string(from: Date())

        var y: CGFloat = view.bounds.height - 36

        // 头部
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.frame = NSRect(x: 16, y: y, width: 80, height: 20)
        timeLabel.font = NSFont.systemFont(ofSize: 10)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        timeLabel.frame = NSRect(x: cardW - 110, y: y + 2, width: 60, height: 16)
        refreshBtn.bezelStyle = .rounded
        refreshBtn.target = self
        refreshBtn.action = #selector(reload)
        refreshBtn.frame = NSRect(x: cardW - 16 - 44, y: y - 2, width: 44, height: 22)
        content.addSubview(titleLabel)
        content.addSubview(timeLabel)
        content.addSubview(refreshBtn)

        y -= 12
        // 本机 Mac
        y = sectionHeader("本机 Mac", at: y)
        y = localCard(at: y)

        y -= 8
        // 服务器健康
        y = sectionHeader(serverSummaryTitle(), at: y)
        let servers = Store.shared.servers.filter { $0.enabled }
        if servers.isEmpty {
            y = infoLine("未配置服务器", at: y)
        } else {
            for (i, server) in servers.prefix(5).enumerated() {
                y = serverRow(server: server, index: i, at: y)
            }
            let alerting = servers.filter {
                guard let st = Store.shared.serverStatus(for: $0.id), st.online else { return false }
                return st.memPercent >= 90 || st.diskPercent >= 85
            }
            if !alerting.isEmpty {
                y = alertBanner(alerting: alerting, at: y)
            }
        }

        y -= 8
        // DeepSeek 余额
        y = sectionHeader("DeepSeek 余额", at: y)
        y = balanceCard(at: y)

        y -= 12
        // 操作按钮
        y = actionButtons(at: y)

        // 裁剪内容高度
        let finalH = max(360, view.bounds.height - y + 8)
        content.frame = NSRect(x: 0, y: 0, width: cardW, height: view.bounds.height)
        contentHeight = view.bounds.height
        // 让 popover 自适应
        if let popover = self.view.window?.contentViewController?.presentingViewController as? NSPopover {
            // 高度调整由 popover contentSize 控制
        }
        // 直接调整 view 高度
        view.frame = NSRect(x: 0, y: 0, width: cardW, height: finalH)
        content.frame = view.bounds
        // 重新排版以适应新高度（从头再来）
        rerenderAll()
    }

    /// 用新 view 高度重排所有内容
    private func rerenderAll() {
        content.subviews = []
        var y: CGFloat = view.bounds.height - 36
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        timeLabel.stringValue = f.string(from: Date())
        titleLabel.frame = NSRect(x: 16, y: y, width: 80, height: 20)
        timeLabel.frame = NSRect(x: cardW - 110, y: y + 2, width: 60, height: 16)
        refreshBtn.frame = NSRect(x: cardW - 16 - 44, y: y - 2, width: 44, height: 22)
        content.addSubview(titleLabel); content.addSubview(timeLabel); content.addSubview(refreshBtn)
        y -= 12
        y = sectionHeader("本机 Mac", at: y)
        y = localCard(at: y)
        y -= 8
        y = sectionHeader(serverSummaryTitle(), at: y)
        let servers = Store.shared.servers.filter { $0.enabled }
        for (i, server) in servers.prefix(5).enumerated() {
            y = serverRow(server: server, index: i, at: y)
        }
        let alerting = servers.filter {
            guard let st = Store.shared.serverStatus(for: $0.id), st.online else { return false }
            return st.memPercent >= 90 || st.diskPercent >= 85
        }
        if !alerting.isEmpty { y = alertBanner(alerting: alerting, at: y) }
        y -= 8
        y = sectionHeader("DeepSeek 余额", at: y)
        y = balanceCard(at: y)
        y -= 12
        y = actionButtons(at: y)
        _ = y
    }

    @objc private func reload() {
        // 同步采集本机（快）
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            var st: LocalStatus?
            LocalMonitor.shared.collect { s in st = s; semaphore.signal() }
            _ = semaphore.wait(timeout: .now() + 3)
            DispatchQueue.main.async {
                self.rebuild()
            }
        }
    }

    // MARK: - 卡片组件

    @discardableResult
    private func sectionHeader(_ text: String, at y: CGFloat) -> CGFloat {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        l.textColor = .labelColor
        l.frame = NSRect(x: 16, y: y - 16, width: cardW - 32, height: 16)
        content.addSubview(l)
        return y - 22
    }

    @discardableResult
    private func infoLine(_ text: String, at y: CGFloat) -> CGFloat {
        let l = NSTextField(labelWithString: "  " + text)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: 16, y: y - 18, width: cardW - 32, height: 16)
        content.addSubview(l)
        return y - 22
    }

    /// 本机卡：3 个 metric 横排 + 内存 Top2
    @discardableResult
    private func localCard(at y: CGFloat) -> CGFloat {
        let cardH: CGFloat = 78
        let card = NSView(frame: NSRect(x: 12, y: y - cardH, width: cardW - 24, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        card.layer?.cornerRadius = 10
        content.addSubview(card)

        // 现采本机（同步快）
        var ls: LocalStatus?
        let sem = DispatchSemaphore(value: 0)
        LocalMonitor.shared.collect { s in ls = s; sem.signal() }
        _ = sem.wait(timeout: .now() + 3)
        guard let ls = ls else { return y - cardH - 4 }

        let metrics: [(String, Double, NSColor, Double)] = [
            ("CPU", ls.cpuPercent, .systemBlue, ls.cpuPercent),
            ("内存", ls.memPercent, MiniBarView.memColor(ls.memPercent), ls.memPercent),
            ("磁盘", ls.diskPercent, MiniBarView.diskColor(ls.diskPercent), ls.diskPercent),
        ]
        var x: CGFloat = 14
        for (name, value, color, barVal) in metrics {
            let lbl = NSTextField(labelWithString: name)
            lbl.font = NSFont.systemFont(ofSize: 10)
            lbl.textColor = .secondaryLabelColor
            lbl.frame = NSRect(x: x, y: cardH - 18, width: 36, height: 12)
            let v = NSTextField(labelWithString: String(format: "%.0f%%", value))
            v.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
            v.textColor = color
            v.frame = NSRect(x: x, y: cardH - 40, width: 80, height: 20)
            let bar = MiniBarView(frame: NSRect(x: x, y: 10, width: 84, height: 6))
            bar.value = barVal
            bar.barColor = color
            card.addSubview(lbl); card.addSubview(v); card.addSubview(bar)
            x += 92
        }
        // 底部一行：型号+温度 / Top1
        let sub = NSTextField(labelWithString: ls.cpuBrand.replacingOccurrences(of: "Intel(R) Core(TM)", with: "").replacingOccurrences(of: " CPU @", with: "") + (ls.cpuTempC > 0 ? String(format: " · 温度 %.1f℃", ls.cpuTempC) : (ls.thermalLevel > 0 ? " · 热级 \(Int(ls.thermalLevel))" : "")))
        sub.font = NSFont.systemFont(ofSize: 10)
        sub.textColor = .secondaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: 14, y: 10, width: cardW - 24 - 14, height: 14)
        card.addSubview(sub)
        return y - cardH - 6
    }

    private func serverSummaryTitle() -> String {
        let servers = Store.shared.servers.filter { $0.enabled }
        let online = servers.filter { Store.shared.serverStatus(for: $0.id)?.online == true }.count
        let alerting = servers.filter {
            guard let st = Store.shared.serverStatus(for: $0.id), st.online else { return false }
            return st.memPercent >= 90 || st.diskPercent >= 85
        }.count
        var s = "服务器健康 · \(online)/\(servers.count) 在线"
        if alerting > 0 { s += " · ⚠️ \(alerting) 台告警" }
        return s
    }

    @discardableResult
    private func serverRow(server: ServerConfig, index: Int, at y: CGFloat) -> CGFloat {
        let rowH: CGFloat = 24
        let card = NSView(frame: NSRect(x: 12, y: y - rowH, width: cardW - 24, height: rowH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 7
        content.addSubview(card)

        let st = Store.shared.serverStatus(for: server.id)
        let online = st?.online ?? false
        let dot = NSView(frame: NSRect(x: 8, y: 8, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = online ? NSColor.systemGreen.cgColor : NSColor.systemRed.cgColor
        card.addSubview(dot)

        let nameBtn = NSButton(title: server.name, target: self, action: #selector(openServer(_:)))
        nameBtn.isBordered = false
        nameBtn.alignment = .left
        nameBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        nameBtn.frame = NSRect(x: 20, y: 1, width: 130, height: 22)
        nameBtn.tag = index
        card.addSubview(nameBtn)

        if let st = st, st.online {
            // 内存条
            let mLabel = NSTextField(labelWithString: "内")
            mLabel.font = NSFont.systemFont(ofSize: 9)
            mLabel.textColor = .secondaryLabelColor
            mLabel.frame = NSRect(x: 150, y: 6, width: 12, height: 12)
            let mBar = MiniBarView(frame: NSRect(x: 164, y: 9, width: 60, height: 6))
            mBar.value = st.memPercent
            mBar.barColor = MiniBarView.memColor(st.memPercent)
            let mPct = NSTextField(labelWithString: String(format: "%.0f%%", st.memPercent))
            mPct.font = NSFont.systemFont(ofSize: 9)
            mPct.textColor = MiniBarView.memColor(st.memPercent)
            mPct.frame = NSRect(x: 226, y: 6, width: 30, height: 12)
            // 磁盘条
            let dLabel = NSTextField(labelWithString: "盘")
            dLabel.font = NSFont.systemFont(ofSize: 9)
            dLabel.textColor = .secondaryLabelColor
            dLabel.frame = NSRect(x: 150, y: -4, width: 12, height: 12)
            let dBar = MiniBarView(frame: NSRect(x: 164, y: -1, width: 60, height: 6))
            dBar.value = st.diskPercent
            dBar.barColor = MiniBarView.diskColor(st.diskPercent)
            let dPct = NSTextField(labelWithString: String(format: "%.0f%%", st.diskPercent))
            dPct.font = NSFont.systemFont(ofSize: 9)
            dPct.textColor = MiniBarView.diskColor(st.diskPercent)
            dPct.frame = NSRect(x: 226, y: -4, width: 30, height: 12)
            [mLabel, mBar, mPct, dLabel, dBar, dPct].forEach { card.addSubview($0) }
        } else {
            let err = NSTextField(labelWithString: st?.error ?? "未采集")
            err.font = NSFont.systemFont(ofSize: 10)
            err.textColor = .systemRed
            err.lineBreakMode = .byTruncatingMiddle
            err.frame = NSRect(x: 150, y: 4, width: 140, height: 16)
            card.addSubview(err)
        }
        return y - rowH - 4
    }

    @discardableResult
    private func alertBanner(alerting: [ServerConfig], at y: CGFloat) -> CGFloat {
        let parts = alerting.map { s -> String in
            let st = Store.shared.serverStatus(for: s.id)
            var msg = s.name
            if let st = st, st.diskPercent >= 85 { msg += " 盘 \(Int(st.diskPercent))%" }
            if let st = st, st.memPercent >= 90 { msg += " 内 \(Int(st.memPercent))%" }
            return msg
        }
        let l = NSTextField(labelWithString: "⚠ " + parts.joined(separator: " · "))
        l.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        l.textColor = .systemRed
        l.lineBreakMode = .byTruncatingMiddle
        l.frame = NSRect(x: 16, y: y - 16, width: cardW - 32, height: 16)
        content.addSubview(l)
        return y - 22
    }

    @discardableResult
    private func balanceCard(at y: CGFloat) -> CGFloat {
        let keys = Store.shared.config.keys.filter { $0.enabled }
        let cardH: CGFloat = max(38, CGFloat(keys.count) * 22 + 14)
        let card = NSView(frame: NSRect(x: 12, y: y - cardH, width: cardW - 24, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.08).cgColor
        card.layer?.cornerRadius = 10
        content.addSubview(card)

        var rowY: CGFloat = cardH - 20
        var total: Double = 0, today: Double = 0, week: Double = 0
        for key in keys {
            let res = Store.shared.result(for: key.id)
            let bal = res.map { $0.total } ?? 0
            total += bal
            today += Store.shared.consumptionToday(for: key.id) ?? 0
            week += Store.shared.consumption(for: key.id, daysAgo: 7) ?? 0
            let n = NSTextField(labelWithString: key.name)
            n.font = NSFont.systemFont(ofSize: 10)
            n.textColor = .secondaryLabelColor
            n.frame = NSRect(x: 14, y: rowY, width: 80, height: 14)
            let v = NSTextField(labelWithString: String(format: "¥%.2f", bal))
            v.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            v.textColor = .labelColor
            v.alignment = .right
            v.frame = NSRect(x: cardW - 24 - 120, y: rowY, width: 120, height: 14)
            card.addSubview(n); card.addSubview(v)
            rowY -= 22
        }
        // 总计行
        if !keys.isEmpty {
            let line = NSView(frame: NSRect(x: 10, y: rowY + 12, width: cardW - 24 - 20, height: 0.5))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.cgColor
            card.addSubview(line)
            let s = NSTextField(labelWithString: "合计")
            s.font = NSFont.systemFont(ofSize: 10)
            s.textColor = .secondaryLabelColor
            s.frame = NSRect(x: 14, y: rowY - 4, width: 60, height: 14)
            let v = NSTextField(labelWithString: String(format: "¥%.2f（今日 %.2f · 7天 %.2f）", total, today, week))
            v.font = NSFont.systemFont(ofSize: 10)
            v.textColor = .secondaryLabelColor
            v.frame = NSRect(x: 70, y: rowY - 4, width: cardW - 24 - 80, height: 14)
            card.addSubview(s); card.addSubview(v)
        }
        return y - cardH - 6
    }

    @discardableResult
    private func actionButtons(at y: CGFloat) -> CGFloat {
        let btnH: CGFloat = 26
        let lineY: CGFloat = y - 10
        let line = NSView(frame: NSRect(x: 12, y: lineY, width: cardW - 24, height: 0.5))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        content.addSubview(line)

        // 两行按钮
        var by: CGFloat = y - 10 - btnH
        let titles1: [(String, Selector)] = [
            ("服务器管理", #selector(openServerManager)),
            ("AI 助手", #selector(openServerChat)),
            ("历史", #selector(openHistory)),
            ("设置", #selector(openSettings)),
        ]
        let w1 = (cardW - 24 - 8 * 3) / 4
        for (i, t) in titles1.enumerated() {
            let btn = NSButton(title: t.0, target: self, action: t.1)
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.frame = NSRect(x: 12 + CGFloat(i) * (w1 + 8), y: by, width: w1, height: btnH)
            content.addSubview(btn)
        }
        by -= btnH + 6
        let titles2: [(String, Selector)] = [
            ("立即刷新", #selector(reload)),
        ]
        for (i, t) in titles2.enumerated() {
            let btn = NSButton(title: t.0, target: self, action: t.1)
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11)
            btn.frame = NSRect(x: 12, y: by, width: cardW - 24, height: btnH)
            content.addSubview(btn)
        }
        return by
    }

    @objc private func openServer(_ sender: NSButton) {
        let servers = Store.shared.servers.filter { $0.enabled }
        guard sender.tag >= 0, sender.tag < servers.count else { return }
        ServerQuickViewController.show(serverId: servers[sender.tag].id)
        if let pop = (view.window?.contentViewController?.presentingViewController as? NSPopover) {
            pop.performClose(nil)
        }
    }
    @objc private func openServerManager() {
        ServerWindowController().showWindow(nil)
        closePopover()
    }
    @objc private func openServerChat() {
        ServerChatWindowController.shared.showWindow(nil)
        closePopover()
    }
    @objc private func openHistory() {
        HistoryWindowController.shared.showWindow(nil)
        closePopover()
    }
    @objc private func openSettings() {
        SettingsWindowController(onChange: {
            NotificationCenter.default.post(name: Notification.Name("DSConfigChanged"), object: nil)
        }).showWindow(nil)
        closePopover()
    }

    private func closePopover() {
        if let pop = (view.window?.contentViewController?.presentingViewController as? NSPopover) {
            pop.performClose(nil)
        }
    }
}
