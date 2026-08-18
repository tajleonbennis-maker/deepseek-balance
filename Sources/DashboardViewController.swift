import AppKit

/// 菜单栏总览（NSPopover）：视觉仪表盘化——大数字色块卡片 + 进度条 + 服务器操作（SSH / AI / 详情）
final class DashboardViewController: NSViewController {

    private let cardW: CGFloat = 340
    private let content = NSView()

    private let titleLabel = NSTextField(labelWithString: "总览")
    private let timeLabel = NSTextField(labelWithString: "")
    private let refreshBtn = NSButton(title: "刷新", target: nil, action: nil)

    private(set) var contentHeight: CGFloat = 600

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: cardW, height: 620))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        view.addSubview(content)
        content.frame = view.bounds
        renderAll()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        renderAll()
    }

    // MARK: - 渲染

    func renderAll() {
        content.subviews = []
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        timeLabel.stringValue = f.string(from: Date())

        var y: CGFloat = view.bounds.height - 38
        // 头部
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.frame = NSRect(x: 16, y: y, width: 60, height: 22)
        timeLabel.font = NSFont.systemFont(ofSize: 10)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        timeLabel.frame = NSRect(x: cardW - 120, y: y + 3, width: 70, height: 16)
        refreshBtn.bezelStyle = .rounded
        refreshBtn.font = NSFont.systemFont(ofSize: 11)
        refreshBtn.target = self
        refreshBtn.action = #selector(reload)
        refreshBtn.frame = NSRect(x: cardW - 16 - 48, y: y - 2, width: 48, height: 24)
        content.addSubview(titleLabel); content.addSubview(timeLabel); content.addSubview(refreshBtn)

        // ===== 本机 Mac：4 个大色块 =====
        y -= 10
        y = sectionHeader("本机 Mac", at: y)
        y = localBigCards(at: y)

        // ===== 服务器 =====
        y -= 6
        y = sectionHeader(serverSummaryTitle(), at: y)
        let servers = Store.shared.servers.filter { $0.enabled }
        if servers.isEmpty {
            y = infoLine("未配置服务器（服务器管理…添加）", at: y)
        } else {
            for (i, server) in servers.prefix(5).enumerated() {
                y = serverCard(server: server, index: i, at: y)
            }
            let alerting = servers.filter {
                guard let st = Store.shared.serverStatus(for: $0.id), st.online else { return false }
                return st.memPercent >= 90 || st.diskPercent >= 85
            }
            if !alerting.isEmpty { y = alertBanner(alerting: alerting, at: y) }
        }

        // ===== DeepSeek 余额 =====
        y -= 6
        y = sectionHeader("DeepSeek 账单", at: y)
        y = balanceCards(at: y)

        // ===== 操作 =====
        y -= 6
        y = actionButtons(at: y)

        // 高度自适应
        let finalH = max(420, view.bounds.height - y + 10)
        view.frame = NSRect(x: 0, y: 0, width: cardW, height: finalH)
        content.frame = view.bounds
        contentHeight = finalH
    }

    @objc private func reload() {
        DispatchQueue.global().async {
            let sem = DispatchSemaphore(value: 0)
            LocalMonitor.shared.collect { _ in sem.signal() }
            _ = sem.wait(timeout: .now() + 3)
            DispatchQueue.main.async { self.renderAll() }
        }
    }

    // MARK: - 组件

    @discardableResult
    private func sectionHeader(_ text: String, at y: CGFloat) -> CGFloat {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        l.frame = NSRect(x: 16, y: y - 17, width: cardW - 32, height: 17)
        content.addSubview(l)
        return y - 23
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

    /// 本机：4 个色块大数字（CPU / 内存 / 磁盘 / 温度）
    @discardableResult
    private func localBigCards(at y: CGFloat) -> CGFloat {
        var ls: LocalStatus?
        let sem = DispatchSemaphore(value: 0)
        LocalMonitor.shared.collect { s in ls = s; sem.signal() }
        _ = sem.wait(timeout: .now() + 3)
        guard let ls = ls else { return y - 100 }

        let cardH: CGFloat = 96
        let card = NSView(frame: NSRect(x: 12, y: y - cardH, width: cardW - 24, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.07).cgColor
        card.layer?.cornerRadius = 12
        content.addSubview(card)

        let items: [(String, String, NSColor)] = [
            ("CPU", String(format: "%.0f%%", ls.cpuPercent), .systemBlue),
            ("内存", String(format: "%.0f%%", ls.memPercent), MiniBarView.memColor(ls.memPercent)),
            ("磁盘", String(format: "%.0f%%", ls.diskPercent), MiniBarView.diskColor(ls.diskPercent)),
            ("温度", ls.cpuTempC > 0 ? String(format: "%.0f°", ls.cpuTempC) : "—", ls.cpuTempC >= 85 ? .systemRed : .systemOrange),
        ]
        let gap: CGFloat = 8
        let bw = (cardW - 24 - gap * 3) / 4
        for (i, it) in items.enumerated() {
            let x = 12 + CGFloat(i) * (bw + gap)
            let tile = NSView(frame: NSRect(x: x, y: 14, width: bw, height: 66))
            tile.wantsLayer = true
            tile.layer?.backgroundColor = it.2.withAlphaComponent(0.12).cgColor
            tile.layer?.cornerRadius = 10
            card.addSubview(tile)

            let n = NSTextField(labelWithString: it.0)
            n.font = NSFont.systemFont(ofSize: 10)
            n.textColor = .secondaryLabelColor
            n.frame = NSRect(x: 8, y: 44, width: bw - 16, height: 14)
            let v = NSTextField(labelWithString: it.1)
            v.font = NSFont.systemFont(ofSize: 19, weight: .semibold)
            v.textColor = it.2
            v.frame = NSRect(x: 8, y: 18, width: bw - 16, height: 24)
            tile.addSubview(n); tile.addSubview(v)
        }
        // 型号行
        let brand = ls.cpuBrand
            .replacingOccurrences(of: "Intel(R) Core(TM)", with: "")
            .replacingOccurrences(of: " CPU @", with: "")
        let sub = NSTextField(labelWithString: brand + (ls.thermalLevel > 0 ? String(format: " · 热级 %d", Int(ls.thermalLevel)) : ""))
        sub.font = NSFont.systemFont(ofSize: 9)
        sub.textColor = .tertiaryLabelColor
        sub.lineBreakMode = .byTruncatingTail
        sub.frame = NSRect(x: 14, y: 3, width: cardW - 24 - 14, height: 12)
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
        var s = "服务器 · \(online)/\(servers.count) 在线"
        if alerting > 0 { s += " · ⚠ \(alerting) 告警" }
        return s
    }

    /// 服务器卡片：名称+IP(可SSH) + 内存/磁盘进度条 + SSH/AI 按钮
    @discardableResult
    private func serverCard(server: ServerConfig, index: Int, at y: CGFloat) -> CGFloat {
        let rowH: CGFloat = 52
        let card = NSView(frame: NSRect(x: 12, y: y - rowH, width: cardW - 24, height: rowH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 10
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        content.addSubview(card)

        let st = Store.shared.serverStatus(for: server.id)
        let online = st?.online ?? false

        // 状态圆点 + 名称 + IP
        let dot = NSView(frame: NSRect(x: 10, y: 26, width: 9, height: 9))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4.5
        dot.layer?.backgroundColor = (online ? NSColor.systemGreen : NSColor.systemRed).cgColor
        card.addSubview(dot)

        let name = NSTextField(labelWithString: server.name)
        name.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        name.frame = NSRect(x: 24, y: 26, width: 120, height: 16)
        card.addSubview(name)

        // IP 可点（SSH）
        let ipBtn = NSButton(title: server.host, target: self, action: #selector(sshServer(_:)))
        ipBtn.isBordered = false
        ipBtn.font = NSFont.systemFont(ofSize: 10)
        ipBtn.contentTintColor = .systemBlue
        ipBtn.alignment = .left
        ipBtn.toolTip = "点击打开终端 SSH 连接"
        ipBtn.frame = NSRect(x: 24, y: 8, width: 120, height: 16)
        ipBtn.tag = index
        card.addSubview(ipBtn)

        if let st = st, st.online {
            // 内存条（上半）
            let mBar = MiniBarView(frame: NSRect(x: 150, y: 28, width: 76, height: 7))
            mBar.value = st.memPercent
            mBar.barColor = MiniBarView.memColor(st.memPercent)
            let mPct = NSTextField(labelWithString: String(format: "%.0f%%", st.memPercent))
            mPct.font = NSFont.systemFont(ofSize: 10)
            mPct.textColor = MiniBarView.memColor(st.memPercent)
            mPct.frame = NSRect(x: 230, y: 25, width: 32, height: 13)
            card.addSubview(mBar); card.addSubview(mPct)
            // 磁盘条（下半）
            let dBar = MiniBarView(frame: NSRect(x: 150, y: 12, width: 76, height: 7))
            dBar.value = st.diskPercent
            dBar.barColor = MiniBarView.diskColor(st.diskPercent)
            let dPct = NSTextField(labelWithString: String(format: "%.0f%%", st.diskPercent))
            dPct.font = NSFont.systemFont(ofSize: 10)
            dPct.textColor = MiniBarView.diskColor(st.diskPercent)
            dPct.frame = NSRect(x: 230, y: 9, width: 32, height: 13)
            card.addSubview(dBar); card.addSubview(dPct)
        } else {
            let err = NSTextField(labelWithString: st?.error ?? "未采集")
            err.font = NSFont.systemFont(ofSize: 10)
            err.textColor = .systemRed
            err.lineBreakMode = .byTruncatingMiddle
            err.frame = NSRect(x: 150, y: 18, width: 100, height: 14)
            card.addSubview(err)
        }

        // 右侧操作按钮：SSH / AI / 详情
        let sshBtn = NSButton(title: "终端", target: self, action: #selector(sshServer(_:)))
        sshBtn.bezelStyle = .rounded
        sshBtn.font = NSFont.systemFont(ofSize: 10)
        sshBtn.tag = index
        sshBtn.frame = NSRect(x: cardW - 24 - 66, y: 26, width: 42, height: 20)
        card.addSubview(sshBtn)

        let aiBtn = NSButton(title: "AI", target: self, action: #selector(aiServer(_:)))
        aiBtn.bezelStyle = .rounded
        aiBtn.font = NSFont.systemFont(ofSize: 10)
        aiBtn.tag = index
        aiBtn.frame = NSRect(x: cardW - 24 - 66, y: 5, width: 42, height: 20)
        card.addSubview(aiBtn)

        let detailBtn = NSButton(title: "…", target: self, action: #selector(openDetail(_:)))
        detailBtn.bezelStyle = .rounded
        detailBtn.font = NSFont.systemFont(ofSize: 11)
        detailBtn.tag = index
        detailBtn.toolTip = "查看详情（趋势/进程/登录）"
        detailBtn.frame = NSRect(x: cardW - 24 - 22, y: 14, width: 20, height: 24)
        card.addSubview(detailBtn)

        return y - rowH - 6
    }

    @discardableResult
    private func alertBanner(alerting: [ServerConfig], at y: CGFloat) -> CGFloat {
        let parts = alerting.map { s -> String in
            let st = Store.shared.serverStatus(for: s.id)
            var msg = s.name
            if let st = st, st.diskPercent >= 85 { msg += " 盘\(Int(st.diskPercent))%" }
            if let st = st, st.memPercent >= 90 { msg += " 内\(Int(st.memPercent))%" }
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

    /// 余额：账号色块卡 + 合计
    @discardableResult
    private func balanceCards(at y: CGFloat) -> CGFloat {
        let keys = Store.shared.config.keys.filter { $0.enabled }
        let cardH: CGFloat = max(52, CGFloat(keys.count) * 30 + 22)
        let card = NSView(frame: NSRect(x: 12, y: y - cardH, width: cardW - 24, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.07).cgColor
        card.layer?.cornerRadius = 12
        content.addSubview(card)

        var rowY: CGFloat = cardH - 26
        var total: Double = 0, today: Double = 0, week: Double = 0
        for key in keys {
            let res = Store.shared.result(for: key.id)
            let bal = res.map { $0.total } ?? 0
            total += bal
            today += Store.shared.consumptionToday(for: key.id) ?? 0
            week += Store.shared.consumption(for: key.id, daysAgo: 7) ?? 0

            // 名称 chip
            let chip = NSView(frame: NSRect(x: 14, y: rowY + 2, width: 78, height: 20))
            chip.wantsLayer = true
            chip.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.1).cgColor
            chip.layer?.cornerRadius = 5
            let n = NSTextField(labelWithString: key.name)
            n.font = NSFont.systemFont(ofSize: 10)
            n.textColor = .systemBlue
            n.alignment = .center
            n.frame = NSRect(x: 0, y: 3, width: 78, height: 14)
            chip.addSubview(n)
            card.addSubview(chip)

            // 余额大数字
            let v = NSTextField(labelWithString: String(format: "¥%.2f", bal))
            v.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
            v.textColor = .labelColor
            v.alignment = .right
            v.frame = NSRect(x: cardW - 24 - 130, y: rowY, width: 130, height: 18)
            card.addSubview(v)
            rowY -= 30
        }
        if !keys.isEmpty {
            let line = NSView(frame: NSRect(x: 12, y: rowY + 16, width: cardW - 24 - 24, height: 0.5))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.separatorColor.cgColor
            card.addSubview(line)
            let s = NSTextField(labelWithString: String(format: "合计 ¥%.2f", total))
            s.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            s.frame = NSRect(x: 14, y: rowY - 2, width: 120, height: 16)
            let u = NSTextField(labelWithString: String(format: "今日 ¥%.2f · 近7天 ¥%.2f", today, week))
            u.font = NSFont.systemFont(ofSize: 10)
            u.textColor = .secondaryLabelColor
            u.frame = NSRect(x: 130, y: rowY - 2, width: cardW - 24 - 140, height: 16)
            card.addSubview(s); card.addSubview(u)
        }
        return y - cardH - 6
    }

    @discardableResult
    private func actionButtons(at y: CGFloat) -> CGFloat {
        let line = NSView(frame: NSRect(x: 12, y: y - 6, width: cardW - 24, height: 0.5))
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.separatorColor.cgColor
        content.addSubview(line)

        var by: CGFloat = y - 12 - 26
        let titles1: [(String, Selector)] = [
            ("服务器管理", #selector(openServerManager)),
            ("AI 助手", #selector(openServerChat)),
            ("历史", #selector(openHistory)),
            ("设置", #selector(openSettings)),
        ]
        let w1 = (cardW - 24 - 8 * 3) / 4
        for (i, t) in titles1.enumerated() {
            let b = NSButton(title: t.0, target: self, action: t.1)
            b.bezelStyle = .rounded
            b.font = NSFont.systemFont(ofSize: 11)
            b.frame = NSRect(x: 12 + CGFloat(i) * (w1 + 8), y: by, width: w1, height: 26)
            content.addSubview(b)
        }
        by -= 32
        let b = NSButton(title: "立即刷新全部数据", target: self, action: #selector(reload))
        b.bezelStyle = .rounded
        b.font = NSFont.systemFont(ofSize: 11)
        b.frame = NSRect(x: 12, y: by, width: cardW - 24, height: 26)
        content.addSubview(b)
        return by
    }

    // MARK: - 服务器操作

    private func server(at index: Int) -> ServerConfig? {
        let servers = Store.shared.servers.filter { $0.enabled }
        guard index >= 0, index < servers.count else { return nil }
        return servers[index]
    }

    /// 打开终端 SSH 连接
    @objc private func sshServer(_ sender: Any) {
        guard let tag = (sender as? NSButton)?.tag ?? (sender as? NSControl)?.tag, let server = server(at: tag) else { return }
        let script = "tell application \"Terminal\" to do script \"ssh \(server.username)@\(server.host)\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
        closePopover()
    }

    /// 打开 AI 助手并选中该服务器
    @objc private func aiServer(_ sender: NSButton) {
        guard let server = server(at: sender.tag) else { return }
        ServerChatWindowController.show(serverId: server.id)
        closePopover()
    }

    @objc private func openDetail(_ sender: NSButton) {
        guard let server = server(at: sender.tag) else { return }
        ServerQuickViewController.show(serverId: server.id)
        closePopover()
    }

    @objc private func openServerManager() { ServerWindowController().showWindow(nil); closePopover() }
    @objc private func openServerChat() { ServerChatWindowController.shared.showWindow(nil); closePopover() }
    @objc private func openHistory() { HistoryWindowController.shared.showWindow(nil); closePopover() }
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
