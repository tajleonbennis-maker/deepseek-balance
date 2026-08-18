import AppKit

/// 单台服务器详情窗：趋势图 + 摘要 + Top 进程 + 登录记录（外访）+ 立即检查
/// 从菜单栏点某台服务器直接打开，单实例按 serverId 复用
final class ServerQuickViewController: NSWindowController {

    // 单例缓存（key: serverId）
    private static var cache: [String: ServerQuickViewController] = [:]

    let serverId: String

    // UI
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let trendView = TrendChartView()
    private let trendTitle = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let procLabel = NSTextField(labelWithString: "")
    private let loginTable = NSTableView()
    private let loginScroll = NSScrollView()
    private let loginTitle = NSTextField(labelWithString: "外访登录记录（谁 / 什么时间 / 来自哪个 IP）")
    private let checkBtn = NSButton(title: "立即检查", target: nil, action: nil)
    private let closeBtn = NSButton(title: "关闭", target: nil, action: nil)
    private let openMgrBtn = NSButton(title: "完整管理…", target: nil, action: nil)

    private init(serverId: String) {
        self.serverId = serverId
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init(window: window)
        window.delegate = nil  // 不拦截 close（我们 manage 缓存）
        buildUI()
        refresh()
    }

    /// 打开（或复用）某台服务器的详情窗
    static func show(serverId: String) {
        if let cached = cache[serverId] {
            cached.showWindow(nil)
        } else {
            let vc = ServerQuickViewController(serverId: serverId)
            cache[serverId] = vc
            vc.showWindow(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let W: CGFloat = 760, H: CGFloat = 540
        let m: CGFloat = 16

        // 顶部：服务器名 + 状态
        nameLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.frame = NSRect(x: m, y: H - m - 26, width: 500, height: 24)
        statusLabel.font = NSFont.systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .right
        statusLabel.frame = NSRect(x: W - m - 200, y: H - m - 24, width: 200, height: 20)
        content.addSubview(nameLabel)
        content.addSubview(statusLabel)

        // 趋势图
        trendTitle.font = NSFont.systemFont(ofSize: 11)
        trendTitle.textColor = .secondaryLabelColor
        trendTitle.frame = NSRect(x: m, y: H - m - 24 - 18, width: W - 2*m, height: 16)
        trendView.frame = NSRect(x: m, y: H - m - 24 - 18 - 116, width: W - 2*m, height: 116)
        content.addSubview(trendTitle)
        content.addSubview(trendView)

        // 摘要
        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.maximumNumberOfLines = 0
        summaryLabel.frame = NSRect(x: m, y: H - m - 24 - 18 - 116 - 18 - 46, width: W - 2*m, height: 46)
        content.addSubview(summaryLabel)

        // Top 进程
        procLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        procLabel.textColor = .secondaryLabelColor
        procLabel.lineBreakMode = .byWordWrapping
        procLabel.maximumNumberOfLines = 0
        procLabel.frame = NSRect(x: m, y: 210, width: W - 2*m, height: 80)
        content.addSubview(procLabel)

        // 登录标题 + 表
        loginTitle.font = NSFont.systemFont(ofSize: 11)
        loginTitle.textColor = .secondaryLabelColor
        loginTitle.frame = NSRect(x: m, y: 188, width: W - 2*m, height: 16)
        content.addSubview(loginTitle)

        let cols: [(String, CGFloat)] = [("time", 130), ("user", 100), ("ip", 220), ("dur", 90)]
        for (id, w) in cols {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = id == "time" ? "时间" : (id == "user" ? "用户" : (id == "ip" ? "来源 IP" : "时长"))
            col.width = w
            loginTable.addTableColumn(col)
        }
        loginTable.rowHeight = 22
        loginTable.usesAlternatingRowBackgroundColors = true
        loginTable.dataSource = self
        loginTable.delegate = self
        loginScroll.frame = NSRect(x: m, y: 64, width: W - 2*m, height: 120)
        loginScroll.hasVerticalScroller = true
        loginScroll.borderType = .bezelBorder
        loginScroll.documentView = loginTable
        content.addSubview(loginScroll)

        // 按钮
        checkBtn.bezelStyle = .rounded
        checkBtn.target = self
        checkBtn.action = #selector(checkNow)
        checkBtn.frame = NSRect(x: m, y: 22, width: 110, height: 28)

        openMgrBtn.bezelStyle = .rounded
        openMgrBtn.target = self
        openMgrBtn.action = #selector(openManager)
        openMgrBtn.frame = NSRect(x: m + 120, y: 22, width: 130, height: 28)

        closeBtn.bezelStyle = .rounded
        closeBtn.keyEquivalent = "\033"  // ESC
        closeBtn.target = self
        closeBtn.action = #selector(close)
        closeBtn.frame = NSRect(x: W - m - 90, y: 22, width: 90, height: 28)

        [checkBtn, openMgrBtn, closeBtn].forEach { content.addSubview($0) }
    }

    // MARK: - 刷新

    private func refresh() {
        guard let server = Store.shared.servers.first(where: { $0.id == serverId }) else { return }
        nameLabel.stringValue = "\(server.name) · \(server.host)"

        let st = Store.shared.serverStatus(for: serverId)
        if let st = st, st.online {
            let memColor = st.memPercent >= 90 ? "🔴" : (st.memPercent >= 75 ? "🟠" : "🟢")
            let diskColor = st.diskPercent >= 85 ? "🔴" : (st.diskPercent >= 70 ? "🟠" : "🟢")
            statusLabel.stringValue = "🟢 在线 · 采集于 \(Self.timeString(st.timestamp))"
            summaryLabel.stringValue = String(format: """
            %@ 内存 %@ %.0f%%（%.0f/%.0f MB，可用 %.0f） · 磁盘 %@ %.0f%%（%.1f/%.1f GB）
            负载 %.2f / %.2f / %.2f · Swap %.0f%%
            """,
            memColor, memColor, st.memPercent, st.memUsedMB, st.memTotalMB, st.memAvailMB,
            diskColor, st.diskPercent, st.diskUsedGB, st.diskTotalGB,
            st.load1, st.load5, st.load15, st.swapPercent)
        } else if let st = st {
            statusLabel.stringValue = "🔴 离线"
            summaryLabel.stringValue = "采集失败：\(st.error ?? "未知错误")"
        } else {
            statusLabel.stringValue = "⚪ 未采集"
            summaryLabel.stringValue = "点击「立即检查」开始采集"
        }

        // 趋势
        let history = Store.shared.serverHistory
            .filter { $0.serverId == serverId }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(30)
            .map { $0 }
        if history.count >= 2 {
            trendView.series = [
                TrendChartView.Series(label: "内存", color: .systemBlue, values: history.map { $0.memPercent }),
                TrendChartView.Series(label: "磁盘", color: .systemOrange, values: history.map { $0.diskPercent }),
                TrendChartView.Series(label: "Swap", color: .systemPurple, values: history.map { $0.swapPercent }),
            ]
            trendView.xLabels = [Self.timeString(history.first!.timestamp), Self.timeString(history.last!.timestamp)]
            trendTitle.stringValue = "资源趋势（最近 \(history.count) 次采集）"
        } else {
            trendView.series = []
            trendTitle.stringValue = "资源趋势：采集 2 次以上后自动生成"
        }

        // 进程
        if let st = st, st.online {
            procLabel.stringValue = st.topProcesses.isEmpty ? "" : Self.formatProcLines(st.topProcesses)
        } else {
            procLabel.stringValue = ""
        }

        loginTable.reloadData()
    }

    private static func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    private static func formatProcLines(_ rows: [String]) -> String {
        var out = "Top 进程（按业务）：\n"
        for row in rows {
            let f = row.split(separator: "|", omittingEmptySubsequences: true).map(String.init)
            if f.count == 5 {
                let biz = f[0].padding(toLength: 14, withPad: " ", startingAt: 0)
                let comm = f[1].padding(toLength: 18, withPad: " ", startingAt: 0)
                let mem = f[2].padding(toLength: 5, withPad: " ", startingAt: 0)
                let cpu = f[3].padding(toLength: 5, withPad: " ", startingAt: 0)
                out += "\(biz)\(comm)  \(mem)% \(cpu)%  pid \(f[4])\n"
            } else {
                out += row + "\n"
            }
        }
        return out
    }

    // MARK: - Actions

    @objc private func checkNow() {
        guard let server = Store.shared.servers.first(where: { $0.id == serverId }) else { return }
        checkBtn.title = "检查中…"
        checkBtn.isEnabled = false
        ServerMonitor.shared.collect(server: server) { [weak self] status in
            DispatchQueue.main.async {
                Store.shared.record(serverStatus: status)
                self?.checkBtn.title = "立即检查"
                self?.checkBtn.isEnabled = true
                self?.refresh()
            }
        }
    }

    @objc private func openManager() {
        ServerWindowController().showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension ServerQuickViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        Store.shared.serverStatus(for: serverId)?.logins.count ?? 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let st = Store.shared.serverStatus(for: serverId), row < st.logins.count,
              let id = tableColumn?.identifier.rawValue else { return nil }
        let lg = st.logins[row]
        let text: String
        switch id {
        case "time": text = lg.time
        case "user": text = lg.user
        case "ip": text = lg.fromIP
        case "dur": text = lg.duration
        default: return nil
        }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
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
}
