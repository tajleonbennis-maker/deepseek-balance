import AppKit

/// 历史记录窗口：告警历史 / 余额历史 / 服务器状态历史（只读，可追溯）
final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    static let shared = HistoryWindowController()

    private let tabView = NSTabView()

    private let alertTable = NSTableView()
    private let balanceTable = NSTableView()
    private let serverTable = NSTableView()
    private let chatTable = NSTableView()

    private let alertScroll = NSScrollView()
    private let balanceScroll = NSScrollView()
    private let serverScroll = NSScrollView()
    private let chatScroll = NSScrollView()

    private let alertCount = NSTextField(labelWithString: "")
    private let balanceCount = NSTextField(labelWithString: "")
    private let serverCount = NSTextField(labelWithString: "")
    private let chatCount = NSTextField(labelWithString: "")

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "历史记录"
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func showWindow(_ sender: Any?) {
        reloadAll()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        tabView.frame = NSRect(x: 0, y: 34, width: 780, height: 506)
        tabView.tabViewType = .topTabsBezelBorder

        let alertTab = NSTabViewItem(identifier: "alerts")
        alertTab.label = "告警历史"
        alertTab.view = buildScroll(alertScroll, table: alertTable,
                                    cols: [("time", "时间", 140), ("cat", "分类", 90), ("subj", "对象", 130), ("body", "内容", 380)])
        alertTab.view?.addSubview(alertCount)
        alertCount.frame = NSRect(x: 8, y: 0, width: 400, height: 18)
        alertCount.font = NSFont.systemFont(ofSize: 10)
        alertCount.textColor = .secondaryLabelColor
        tabView.addTabViewItem(alertTab)

        let balanceTab = NSTabViewItem(identifier: "balance")
        balanceTab.label = "余额历史"
        balanceTab.view = buildScroll(balanceScroll, table: balanceTable,
                                      cols: [("day", "日期", 110), ("name", "账号", 170), ("open", "期初", 100), ("close", "期末", 100), ("delta", "当日消耗", 110)])
        balanceTab.view?.addSubview(balanceCount)
        balanceCount.frame = NSRect(x: 8, y: 0, width: 400, height: 18)
        balanceCount.font = NSFont.systemFont(ofSize: 10)
        balanceCount.textColor = .secondaryLabelColor
        tabView.addTabViewItem(balanceTab)

        let serverTab = NSTabViewItem(identifier: "server")
        serverTab.label = "服务器状态"
        serverTab.view = buildScroll(serverScroll, table: serverTable,
                                     cols: [("time", "采集时间", 150), ("name", "服务器", 150), ("status", "状态", 60), ("mem", "内存%", 70), ("disk", "磁盘%", 70), ("swap", "Swap%", 70), ("load", "负载", 80)])
        serverTab.view?.addSubview(serverCount)
        serverCount.frame = NSRect(x: 8, y: 0, width: 400, height: 18)
        serverCount.font = NSFont.systemFont(ofSize: 10)
        serverCount.textColor = .secondaryLabelColor
        tabView.addTabViewItem(serverTab)

        let chatTab = NSTabViewItem(identifier: "chat")
        chatTab.label = "操作日志"
        chatTab.view = buildScroll(chatScroll, table: chatTable,
                                   cols: [("time", "时间", 140), ("server", "服务器", 120), ("summary", "内容摘要", 460)])
        chatTable.target = self
        chatTable.doubleAction = #selector(chatDoubleClicked)
        chatTab.view?.addSubview(chatCount)
        chatCount.frame = NSRect(x: 8, y: 0, width: 400, height: 18)
        chatCount.font = NSFont.systemFont(ofSize: 10)
        chatCount.textColor = .secondaryLabelColor
        tabView.addTabViewItem(chatTab)

        content.addSubview(tabView)

        // 底部状态条
        let hint = NSTextField(labelWithString: "告警保留 90 天 · 余额快照保留 60 天 · 服务器状态保留 7 天 · 操作日志保留 30 天（双击操作日志可看完整对话）")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: 8, y: 8, width: 700, height: 16)
        content.addSubview(hint)
    }

    private func buildScroll(_ scroll: NSScrollView, table: NSTableView,
                             cols: [(id: String, title: String, width: CGFloat)]) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 470))
        scroll.frame = NSRect(x: 12, y: 22, width: 756, height: 438)
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        table.usesAlternatingRowBackgroundColors = true
        for c in cols {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.id))
            col.title = c.title
            col.width = c.width
            table.addTableColumn(col)
        }
        scroll.documentView = table
        container.addSubview(scroll)
        return container
    }

    // MARK: - 数据

    private func reloadAll() {
        let alerts = Store.shared.alerts.reversed()
        alertCount.stringValue = "共 \(Store.shared.alerts.count) 条告警记录"
        let balances = Store.shared.records.sorted { $0.day > $1.day }
        balanceCount.stringValue = "共 \(balances.count) 天 × \(Store.shared.config.keys.count) 个账号的快照"
        let servers = Store.shared.serverHistory.sorted { $0.timestamp > $1.timestamp }
        serverCount.stringValue = "共 \(servers.count) 次采集（最近 7 天）"
        chatCount.stringValue = "共 \(Store.shared.chatLogs.count) 次 AI 助手会话（最近 30 天）"
        alertTable.reloadData()
        balanceTable.reloadData()
        serverTable.reloadData()
        chatTable.reloadData()
    }

    private func keyName(_ id: String) -> String {
        Store.shared.config.keys.first(where: { $0.id == id })?.name ?? "未知账号"
    }

    private func serverName(_ id: String) -> String {
        Store.shared.servers.first(where: { $0.id == id })?.name ?? id
    }

    // MARK: - TableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === alertTable { return Store.shared.alerts.count }
        if tableView === balanceTable { return Store.shared.records.count }
        if tableView === serverTable { return Store.shared.serverHistory.count }
        if tableView === chatTable { return Store.shared.chatLogs.count }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        let text: String
        var color = NSColor.labelColor

        if tableView === alertTable {
            let alerts = Store.shared.alerts.reversed()
            guard row < alerts.count else { return nil }
            let a = Array(alerts)[row]
            switch id {
            case "time": text = Self.timeStr(a.timestamp)
            case "cat": text = a.category
            case "subj": text = a.subject
            case "body":
                text = a.body
                color = a.category == "服务器告警" ? .systemRed : .secondaryLabelColor
            default: return nil
            }
        } else if tableView === balanceTable {
            let recs = Store.shared.records.sorted { $0.day > $1.day }
            guard row < recs.count else { return nil }
            let r = recs[row]
            switch id {
            case "day": text = r.day
            case "name": text = keyName(r.keyId)
            case "open": text = "¥" + String(format: "%.2f", r.open)
            case "close": text = "¥" + String(format: "%.2f", r.close)
            case "delta":
                let d = r.open - r.close
                text = d > 0 ? "-¥" + String(format: "%.2f", d) : (d < 0 ? "+¥" + String(format: "%.2f", -d) : "0")
                color = d > 0 ? .systemOrange : (d < 0 ? .systemGreen : .labelColor)
            default: return nil
            }
        } else if tableView === serverTable {
            let hs = Store.shared.serverHistory.sorted { $0.timestamp > $1.timestamp }
            guard row < hs.count else { return nil }
            let h = hs[row]
            switch id {
            case "time": text = Self.timeStr(h.timestamp)
            case "name": text = serverName(h.serverId)
            case "status": text = h.online ? "在线" : "离线"
            case "mem": text = String(format: "%.0f%%", h.memPercent)
            case "disk": text = String(format: "%.0f%%", h.diskPercent)
            case "swap": text = String(format: "%.0f%%", h.swapPercent)
            case "load": text = String(format: "%.2f", h.load1)
            default: return nil
            }
        } else if tableView === chatTable {
            let logs = Store.shared.chatLogs.sorted { $0.timestamp > $1.timestamp }
            guard row < logs.count else { return nil }
            let log = logs[row]
            switch id {
            case "time": text = Self.timeStr(log.timestamp)
            case "server": text = log.serverName
            case "summary":
                // 摘要：最后一条有效内容
                if let last = log.entries.last {
                    text = "\(last.content.replacingOccurrences(of: "\n", with: " ").prefix(80))"
                } else { text = "（空）" }
            default: return nil
            }
        } else {
            return nil
        }

        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        cell.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private static func timeStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        return f.string(from: d)
    }

    /// 双击操作日志：弹窗查看完整对话
    @objc private func chatDoubleClicked() {
        let row = chatTable.clickedRow
        let logs = Store.shared.chatLogs.sorted { $0.timestamp > $1.timestamp }
        guard row >= 0, row < logs.count else { return }
        let log = logs[row]

        var body = "时间：\(Self.timeStr(log.timestamp))    服务器：\(log.serverName)\n\n"
        for e in log.entries {
            switch e.role {
            case "user": body += "🧑 我：\n\(e.content)\n\n"
            case "assistant": body += "🤖 DeepSeek：\n\(e.content)\n\n"
            case "command": body += "🔧 命令：\n\(e.content)\n\n"
            case "result": body += "📥 执行结果：\n\(e.content)\n\n"
            default: body += "\(e.role)：\n\(e.content)\n\n"
            }
        }
        let alert = NSAlert()
        alert.messageText = "操作日志（\(log.serverName)）"
        alert.informativeText = body
        alert.addButton(withTitle: "关闭")
        alert.accessoryView = nil
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
