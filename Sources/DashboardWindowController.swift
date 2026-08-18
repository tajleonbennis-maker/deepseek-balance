import AppKit

/// 总览仪表盘：一屏看本机 / 服务器 / 余额（卡片化 + 进度条，点击服务器行进详情）
final class DashboardWindowController: NSWindowController, NSWindowDelegate {

    static let shared = DashboardWindowController()

    // 根容器（每次刷新重建子视图）
    private let root = NSView()
    private let refreshBtn = NSButton(title: "刷新", target: nil, action: nil)
    private let lastUpdateLabel = NSTextField(labelWithString: "")

    private let winW: CGFloat = 700
    private let winH: CGFloat = 560

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "总览仪表盘"
        super.init(window: window)
        window.delegate = self
        window.contentView = root
        buildHeader()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func showWindow(_ sender: Any?) {
        refresh()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - 头部

    private func buildHeader() {
        let title = NSTextField(labelWithString: "总览仪表盘")
        title.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        title.frame = NSRect(x: 16, y: winH - 34, width: 200, height: 22)
        lastUpdateLabel.font = NSFont.systemFont(ofSize: 11)
        lastUpdateLabel.textColor = .secondaryLabelColor
        lastUpdateLabel.alignment = .right
        lastUpdateLabel.frame = NSRect(x: winW - 260, y: winH - 32, width: 150, height: 16)
        refreshBtn.bezelStyle = .rounded
        refreshBtn.target = self
        refreshBtn.action = #selector(refreshAction)
        refreshBtn.frame = NSRect(x: winW - 100, y: winH - 36, width: 70, height: 26)
        root.addSubview(title)
        root.addSubview(lastUpdateLabel)
        root.addSubview(refreshBtn)
    }

    @objc private func refreshAction() {
        refresh()
    }

    // MARK: - 刷新（重建内容）

    private func refresh() {
        // 清除除头部外的子视图
        for v in root.subviews where v !== refreshBtn && v !== lastUpdateLabel &&
            !(v is NSTextField && v.frame.minY > winH - 40) {
            // 保留标题 label（minY > winH-40 的是标题），其余删
        }
        root.subviews = root.subviews.filter { v in
            v === refreshBtn || v === lastUpdateLabel || (v is NSTextField && v.frame.minY > winH - 40)
        }

        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        lastUpdateLabel.stringValue = "刷新于 \(df.string(from: Date()))"

        var y = winH - 52

        // ===== 本机 Mac 卡 =====
        y = cardSection(title: "本机 Mac", y: y)
        if let ls = localStatus() {
            y = localMetrics(status: ls, y: y)
        } else {
            y = infoLine("本机状态采集中…", y: y)
        }

        // ===== 服务器健康卡 =====
        y -= 12
        y = cardSection(title: serverSummaryTitle(), y: y)
        let servers = Store.shared.servers.filter { $0.enabled }
        if servers.isEmpty {
            y = infoLine("未配置服务器 —— 菜单栏「服务器管理…」添加", y: y)
        } else {
            for (i, server) in servers.enumerated() {
                y = serverRow(server: server, index: i, y: y)
            }
            // 告警横幅
            let alerting = servers.filter {
                guard let st = Store.shared.serverStatus(for: $0.id), st.online else { return false }
                return st.memPercent >= 90 || st.diskPercent >= 85
            }
            if !alerting.isEmpty {
                y = alertBanner(servers: alerting, y: y)
            }
        }

        // ===== DeepSeek 余额卡 =====
        y -= 12
        y = cardSection(title: "DeepSeek 余额", y: y)
        y = balanceCard(y: y)

        // 底部留白
        _ = y
    }

    private func localStatus() -> LocalStatus? {
        // 从 StatusMenuController 取不到（不同实例），直接用 LocalMonitor 现采一份（非阻塞则用缓存）
        // 简化：重新采集（快，几十 ms ~ 1s）
        let semaphore = DispatchSemaphore(value: 0)
        var st: LocalStatus?
        LocalMonitor.shared.collect { s in
            st = s
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 3)
        return st
    }

    // MARK: - 卡片工具

    /// 返回新的 y（卡片标题下方起始）
    private func cardSection(title: String, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.frame = NSRect(x: 16, y: y - 20, width: 500, height: 18)
        root.addSubview(label)
        return y - 24
    }

    private func infoLine(_ text: String, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: "  " + text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 16, y: y - 24, width: winW - 32, height: 20)
        root.addSubview(label)
        return y - 28
    }

    private func localMetrics(status ls: LocalStatus, y: CGFloat) -> CGFloat {
        // 浅灰卡片底
        let card = NSView(frame: NSRect(x: 16, y: y - 86, width: winW - 32, height: 82))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.07).cgColor
        card.layer?.cornerRadius = 12
        root.addSubview(card)

        let metrics: [(String, Double, NSColor, Double)] = [
            ("CPU", ls.cpuPercent, .systemBlue, ls.cpuPercent),
            ("内存", ls.memPercent, MiniBarView.memColor(ls.memPercent), ls.memPercent),
            ("磁盘", ls.diskPercent, MiniBarView.diskColor(ls.diskPercent), ls.diskPercent),
        ]
        var x: CGFloat = 30
        for (name, value, color, barVal) in metrics {
            let label = NSTextField(labelWithString: name)
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: x, y: y - 18, width: 50, height: 14)
            let valueLabel = NSTextField(labelWithString: String(format: "%.0f%%", value))
            valueLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
            valueLabel.textColor = color
            valueLabel.frame = NSRect(x: x, y: y - 44, width: 90, height: 24)
            let bar = MiniBarView(frame: NSRect(x: x, y: y - 62, width: 120, height: 8))
            bar.value = barVal
            bar.barColor = color
            card.addSubview(label)
            card.addSubview(valueLabel)
            card.addSubview(bar)
            x += 150
        }
        // 内存 Top2
        let topLabel = NSTextField(labelWithString: "内存 Top")
        topLabel.font = NSFont.systemFont(ofSize: 11)
        topLabel.textColor = .secondaryLabelColor
        topLabel.frame = NSRect(x: 500, y: y - 18, width: 80, height: 14)
        card.addSubview(topLabel)
        let tops = ls.topProcesses.prefix(2)
        var ty: CGFloat = y - 38
        for t in tops {
            let l = NSTextField(labelWithString: String(format: "%@ %.1fG", t.name, t.memGB))
            l.font = NSFont.systemFont(ofSize: 11)
            l.textColor = .labelColor
            l.frame = NSRect(x: 500, y: ty, width: 170, height: 14)
            card.addSubview(l)
            ty -= 16
        }

        return y - 90
    }

    private func serverSummaryTitle() -> String {
        let servers = Store.shared.servers.filter { $0.enabled }
        let online = servers.filter {
            Store.shared.serverStatus(for: $0.id)?.online == true
        }.count
        let alerting = servers.filter {
            guard let st = Store.shared.serverStatus(for: $0.id), st.online else { return false }
            return st.memPercent >= 90 || st.diskPercent >= 85
        }.count
        if alerting > 0 {
            return "服务器健康 · \(online)/\(servers.count) 在线 · ⚠️ \(alerting) 台告警"
        }
        return "服务器健康 · \(online)/\(servers.count) 在线"
    }

    private func serverRow(server: ServerConfig, index: Int, y: CGFloat) -> CGFloat {
        let rowH: CGFloat = 30
        let rowY = y - rowH - 4
        let row = NSView(frame: NSRect(x: 16, y: rowY, width: winW - 32, height: rowH))
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        row.layer?.cornerRadius = 8
        row.layer?.borderWidth = 0.5
        row.layer?.borderColor = NSColor.separatorColor.cgColor

        let st = Store.shared.serverStatus(for: server.id)
        let online = st?.online ?? false

        // 状态圆点
        let dot = NSView(frame: NSRect(x: 12, y: 11, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = online ? NSColor.systemGreen.cgColor : NSColor.systemRed.cgColor
        row.addSubview(dot)

        // 名称（可点进详情）
        let nameBtn = NSButton(title: server.name, target: self, action: #selector(openServerDetail(_:)))
        nameBtn.isBordered = false
        nameBtn.alignment = .left
        nameBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        nameBtn.frame = NSRect(x: 26, y: 2, width: 150, height: 26)
        nameBtn.tag = index
        row.addSubview(nameBtn)

        if let st = st, st.online {
            addBar(row: row, label: "内存", x: 190, value: st.memPercent,
                   color: MiniBarView.memColor(st.memPercent))
            addBar(row: row, label: "磁盘", x: 340, value: st.diskPercent,
                   color: MiniBarView.diskColor(st.diskPercent))
            let load = NSTextField(labelWithString: String(format: "负载 %.2f", st.load1))
            load.font = NSFont.systemFont(ofSize: 11)
            load.textColor = .secondaryLabelColor
            load.frame = NSRect(x: 495, y: 7, width: 80, height: 16)
            row.addSubview(load)
            let detail = NSTextField(labelWithString: "查看详情 →")
            detail.font = NSFont.systemFont(ofSize: 11)
            detail.textColor = .secondaryLabelColor
            detail.alignment = .right
            detail.frame = NSRect(x: winW - 32 - 110, y: 7, width: 100, height: 16)
            row.addSubview(detail)
        } else {
            let err = NSTextField(labelWithString: st?.error ?? "未采集")
            err.font = NSFont.systemFont(ofSize: 11)
            err.textColor = .systemRed
            err.lineBreakMode = .byTruncatingTail
            err.frame = NSRect(x: 190, y: 7, width: 300, height: 16)
            row.addSubview(err)
        }

        root.addSubview(row)
        return rowY
    }

    private func addBar(row: NSView, label: String, x: CGFloat, value: Double, color: NSColor) {
        let l = NSTextField(labelWithString: label)
        l.font = NSFont.systemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        l.frame = NSRect(x: x, y: 7, width: 34, height: 16)
        let bar = MiniBarView(frame: NSRect(x: x + 36, y: 10, width: 70, height: 10))
        bar.value = value
        bar.barColor = color
        let v = NSTextField(labelWithString: String(format: "%.0f%%", value))
        v.font = NSFont.systemFont(ofSize: 11)
        v.textColor = color
        v.frame = NSRect(x: x + 110, y: 7, width: 40, height: 16)
        row.addSubview(l)
        row.addSubview(bar)
        row.addSubview(v)
    }

    private func alertBanner(servers: [ServerConfig], y: CGFloat) -> CGFloat {
        let parts = servers.map { s -> String in
            let st = Store.shared.serverStatus(for: s.id)
            var msg = s.name
            if let st = st, st.diskPercent >= 85 { msg += " 磁盘 \(Int(st.diskPercent))%" }
            if let st = st, st.memPercent >= 90 { msg += " 内存 \(Int(st.memPercent))%" }
            return msg
        }
        let label = NSTextField(labelWithString: "⚠ 告警：" + parts.joined(separator: " · "))
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .systemRed
        label.frame = NSRect(x: 28, y: y - 26, width: winW - 56, height: 18)
        root.addSubview(label)
        return y - 30
    }

    private func balanceCard(y: CGFloat) -> CGFloat {
        let keys = Store.shared.config.keys.filter { $0.enabled }
        let cardH: CGFloat = 46
        let cardY = y - cardH - 6
        let card = NSView(frame: NSRect(x: 16, y: cardY, width: winW - 32, height: cardH))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.07).cgColor
        card.layer?.cornerRadius = 12
        root.addSubview(card)

        var x: CGFloat = 24
        for key in keys {
            let res = Store.shared.result(for: key.id)
            let name = NSTextField(labelWithString: key.name)
            name.font = NSFont.systemFont(ofSize: 11)
            name.textColor = .secondaryLabelColor
            name.frame = NSRect(x: x, y: cardY + cardH - 34, width: 120, height: 14)
            let bal = res.map { String(format: "¥%.2f", $0.total) } ?? "—"
            let value = NSTextField(labelWithString: bal)
            value.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            value.textColor = .labelColor
            value.frame = NSRect(x: x, y: cardY + 6, width: 120, height: 20)
            card.addSubview(name)
            card.addSubview(value)
            x += 130
        }

        // 今日消耗 / 近 7 天
        var todaySum = 0.0, weekSum = 0.0
        for key in keys {
            todaySum += Store.shared.consumptionToday(for: key.id) ?? 0
            weekSum += Store.shared.consumption(for: key.id, daysAgo: 7) ?? 0
        }
        let tLabel = NSTextField(labelWithString: "今日消耗")
        tLabel.font = NSFont.systemFont(ofSize: 11)
        tLabel.textColor = .secondaryLabelColor
        tLabel.frame = NSRect(x: winW - 240, y: cardY + cardH - 34, width: 80, height: 14)
        let tVal = NSTextField(labelWithString: String(format: "¥%.2f", todaySum))
        tVal.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        tVal.textColor = .systemOrange
        tVal.frame = NSRect(x: winW - 240, y: cardY + 6, width: 100, height: 20)
        let wLabel = NSTextField(labelWithString: "近 7 天")
        wLabel.font = NSFont.systemFont(ofSize: 11)
        wLabel.textColor = .secondaryLabelColor
        wLabel.frame = NSRect(x: winW - 130, y: cardY + cardH - 34, width: 60, height: 14)
        let wVal = NSTextField(labelWithString: String(format: "¥%.2f", weekSum))
        wVal.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        wVal.textColor = .labelColor
        wVal.frame = NSRect(x: winW - 130, y: cardY + 6, width: 100, height: 20)
        card.addSubview(tLabel); card.addSubview(tVal)
        card.addSubview(wLabel); card.addSubview(wVal)

        return cardY - 10
    }

    // MARK: - Actions

    @objc private func openServerDetail(_ sender: NSButton) {
        let servers = Store.shared.servers.filter { $0.enabled }
        guard sender.tag >= 0, sender.tag < servers.count else { return }
        ServerQuickViewController.show(serverId: servers[sender.tag].id)
    }
}
