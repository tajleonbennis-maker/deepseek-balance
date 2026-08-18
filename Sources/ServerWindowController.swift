import AppKit
import UniformTypeIdentifiers

/// 服务器管理窗口：添加/编辑/删除服务器，查看健康状态（内存/CPU/磁盘/进程/登录审计），导出 CSV
final class ServerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    // 服务器列表
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let addBtn = NSButton()
    private let editBtn = NSButton()
    private let delBtn = NSButton()
    private let exportBtn = NSButton()
    private let checkBtn = NSButton(title: "立即检查全部", target: nil, action: nil)

    // 详情
    private let summaryLabel = NSTextField(labelWithString: "选中服务器查看详情")
    private let procLabel = NSTextField(labelWithString: "")
    private let loginTable = NSTableView()
    private let loginScroll = NSScrollView()
    private let loginTitle = NSTextField(labelWithString: "最近登录记录（谁 / 什么时间 / 来自哪个 IP）")

    private let winW: CGFloat = 660
    private let winH: CGFloat = 560

    private var isChecking = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "服务器管理"
        super.init(window: window)
        window.delegate = self
        buildUI()
        reloadServers()
        refreshDetails()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func showWindow(_ sender: Any?) {
        reloadServers()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - UI（纯 frame 布局）

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let margin: CGFloat = 16

        // 服务器列表
        setupTable(tableView, columns: [("name", "名称", 100), ("host", "主机", 140), ("user", "用户", 80), ("status", "状态", 70), ("mem", "内存", 90), ("disk", "磁盘", 80)])
        scrollView.frame = NSRect(x: margin, y: winH - margin - 170, width: winW - 2*margin, height: 170)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView
        content.addSubview(scrollView)

        // 按钮行
        let btnY = winH - margin - 170 - 38
        setupButton(addBtn, "＋ 添加", #selector(addServer), NSRect(x: margin, y: btnY, width: 80, height: 28))
        setupButton(editBtn, "编辑", #selector(editServer), NSRect(x: margin + 88, y: btnY, width: 60, height: 28))
        setupButton(delBtn, "删除", #selector(deleteServer), NSRect(x: margin + 156, y: btnY, width: 60, height: 28))
        setupButton(exportBtn, "导出 CSV", #selector(exportCSV), NSRect(x: winW - margin - 270, y: btnY, width: 90, height: 28))
        setupButton(checkBtn, "立即检查全部", #selector(checkAll), NSRect(x: winW - margin - 170, y: btnY, width: 110, height: 28))
        [addBtn, editBtn, delBtn, exportBtn, checkBtn].forEach { content.addSubview($0) }

        // 详情摘要
        summaryLabel.font = NSFont.systemFont(ofSize: 12)
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.maximumNumberOfLines = 0
        summaryLabel.frame = NSRect(x: margin, y: btnY - 44, width: winW - 2*margin, height: 40)
        content.addSubview(summaryLabel)

        // Top 进程
        procLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        procLabel.lineBreakMode = .byWordWrapping
        procLabel.maximumNumberOfLines = 0
        procLabel.textColor = .secondaryLabelColor
        procLabel.frame = NSRect(x: margin, y: btnY - 44 - 78, width: winW - 2*margin, height: 72)
        content.addSubview(procLabel)

        // 登录审计
        loginTitle.font = NSFont.systemFont(ofSize: 11)
        loginTitle.textColor = .secondaryLabelColor
        loginTitle.frame = NSRect(x: margin, y: btnY - 44 - 78 - 24, width: winW - 2*margin, height: 18)
        content.addSubview(loginTitle)

        setupTable(loginTable, columns: [("time", "时间", 130), ("user", "用户", 100), ("ip", "来源 IP", 180), ("dur", "时长", 90)])
        loginScroll.frame = NSRect(x: margin, y: margin, width: winW - 2*margin, height: 120)
        loginScroll.hasVerticalScroller = true
        loginScroll.borderType = .bezelBorder
        loginScroll.documentView = loginTable
        content.addSubview(loginScroll)

        let hint = NSTextField(labelWithString: "密码本地明文存储，仅用于本机 SSH 采集；导出 CSV 含密码，请妥善保管。")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.frame = NSRect(x: margin, y: margin + 124, width: winW - 2*margin, height: 14)
        content.addSubview(hint)
    }

    private func setupTable(_ table: NSTableView, columns: [(id: String, title: String, width: CGFloat)]) {
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        table.allowsColumnReordering = false
        table.usesAlternatingRowBackgroundColors = true
        for c in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.id))
            col.title = c.title
            col.width = c.width
            table.addTableColumn(col)
        }
    }

    private func setupButton(_ btn: NSButton, _ title: String, _ action: Selector, _ frame: NSRect) {
        btn.title = title
        btn.bezelStyle = .rounded
        btn.target = self
        btn.action = action
        btn.frame = frame
        btn.translatesAutoresizingMaskIntoConstraints = true
    }

    // MARK: - 数据

    private func reloadServers() {
        tableView.reloadData()
        // 恢复选中
        if tableView.selectedRow < 0, !Store.shared.servers.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        refreshDetails()
    }

    private func refreshDetails() {
        let servers = Store.shared.servers
        let row = tableView.selectedRow
        guard row >= 0, row < servers.count else {
            summaryLabel.stringValue = servers.isEmpty ? "尚未添加服务器 — 点「＋ 添加」" : "选中一台服务器查看详情"
            procLabel.stringValue = ""
            loginTable.reloadData()
            return
        }
        let server = servers[row]
        let st = Store.shared.serverStatus(for: server.id)
        guard let st = st else {
            summaryLabel.stringValue = "\(server.name)（\(server.host)）— 尚未采集，点「立即检查全部」"
            procLabel.stringValue = ""
            loginTable.reloadData()
            return
        }
        if !st.online {
            summaryLabel.stringValue = "\(server.name)（\(server.host)）— 🔴 采集失败：\(st.error ?? "未知错误")"
            procLabel.stringValue = ""
            loginTable.reloadData()
            return
        }
        let memColor = st.memPercent >= 90 ? "🔴" : (st.memPercent >= 75 ? "🟠" : "🟢")
        let diskColor = st.diskPercent >= 85 ? "🔴" : (st.diskPercent >= 70 ? "🟠" : "🟢")
        summaryLabel.stringValue = String(format: """
        %@（%@）%@  内存 %@ %.0f%%（%.0f/%.0f MB，可用 %.0f） · 磁盘 %@ %.0f%%（%.1f/%.1f GB）
        负载 %.2f / %.2f / %.2f · Swap %.0f%% · 采集于 %@
        """,
        server.name, server.host, st.online ? "🟢" : "🔴",
        memColor, st.memPercent, st.memUsedMB, st.memTotalMB, st.memAvailMB,
        diskColor, st.diskPercent, st.diskUsedGB, st.diskTotalGB,
        st.load1, st.load5, st.load15, st.swapPercent, Self.timeString(st.timestamp))

        procLabel.stringValue = st.topProcesses.isEmpty ? "" : Self.formatProcLines(st.topProcesses)
        loginTable.reloadData()
    }

    private static func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: d)
    }

    /// 格式化 Top 进程展示：业务名 + 进程名 + 内存% + CPU% + PID（按业务名 14 字、comm 18 字固定列宽对齐）
    private static func formatProcLines(_ rows: [String]) -> String {
        var out = "Top 进程（按业务）：\n"
        for row in rows {
            let f = row.split(separator: "|", omittingEmptySubsequences: true).map(String.init)
            if f.count == 5 {
                let biz = f[0].padding(toLength: 14, withPad: " ", startingAt: 0)
                let comm = f[1].padding(toLength: 18, withPad: " ", startingAt: 0)
                out += String(format: "%@%@  %5s%% %5s%%  pid %@\n", biz, comm, f[2], f[3], f[4])
            } else {
                out += row + "\n"
            }
        }
        return out
    }

    // MARK: - TableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === self.tableView { return Store.shared.servers.count }
        guard let sid = selectedServerId(),
              let st = Store.shared.serverStatus(for: sid) else { return 0 }
        return st.logins.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        if tableView === self.tableView {
            let servers = Store.shared.servers
            guard row < servers.count else { return nil }
            let server = servers[row]
            let st = Store.shared.serverStatus(for: server.id)
            let text: String
            switch id {
            case "name": text = server.name
            case "host": text = server.host
            case "user": text = server.username
            case "status":
                if let st = st { text = st.online ? "正常" : "失败" }
                else { text = "未采集" }
            case "mem":
                if let st = st, st.online { text = String(format: "%.0f%%", st.memPercent) }
                else { text = "—" }
            case "disk":
                if let st = st, st.online { text = String(format: "%.0f%%", st.diskPercent) }
                else { text = "—" }
            default: return nil
            }
            return cell(text: text, color: id == "status" ? (st?.online == true ? .systemGreen : .systemRed) : (id == "mem" && (st?.memPercent ?? 0) >= 90 ? .systemRed : .labelColor))
        } else {
            guard let sid = selectedServerId(),
                  let st = Store.shared.serverStatus(for: sid) else { return nil }
            guard row < st.logins.count else { return nil }
            let lg = st.logins[row]
            let text: String
            switch id {
            case "time": text = lg.time
            case "user": text = lg.user
            case "ip": text = lg.fromIP
            case "dur": text = lg.duration
            default: return nil
            }
            return cell(text: text, color: .labelColor)
        }
    }

    private func cell(text: String, color: NSColor) -> NSView {
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === self.tableView {
            refreshDetails()
        }
    }

    private func selectedServerId() -> String? {
        let servers = Store.shared.servers
        let row = tableView.selectedRow
        guard row >= 0, row < servers.count else { return nil }
        return servers[row].id
    }

    // MARK: - 增删改

    @objc private func addServer() { promptServer(existing: nil) }

    @objc private func editServer() {
        guard let sid = selectedServerId(),
              let server = Store.shared.servers.first(where: { $0.id == sid }) else { NSSound.beep(); return }
        promptServer(existing: server)
    }

    @objc private func deleteServer() {
        guard let sid = selectedServerId(),
              let server = Store.shared.servers.first(where: { $0.id == sid }) else { NSSound.beep(); return }
        let alert = NSAlert()
        alert.messageText = "删除服务器「\(server.name)」？"
        alert.informativeText = "仅移除本地配置。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Store.shared.removeServer(id: sid)
            reloadServers()
        }
    }

    private func promptServer(existing: ServerConfig?) {
        let alert = NSAlert()
        alert.messageText = existing == nil ? "添加服务器" : "编辑「\(existing!.name)」"
        alert.informativeText = "填写 SSH 登录信息（IP 可带端口，如 1.2.3.4 或 1.2.3.4:22）"

        // 纯 frame 布局
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 160))
        let labels = ["名称", "主机 IP", "用户名", "密码"]
        let ys: [CGFloat] = [126, 88, 50, 12]
        var fields: [NSTextField] = []
        for (i, lb) in labels.enumerated() {
            let label = NSTextField(labelWithString: lb)
            label.frame = NSRect(x: 0, y: ys[i] + 4, width: 60, height: 18)
            let field: NSTextField
            if i == 3 {
                field = NSSecureTextField(string: existing?.password ?? "")
            } else {
                field = NSTextField(string: [existing?.name, existing?.host, existing?.username][i] ?? "")
            }
            field.frame = NSRect(x: 66, y: ys[i], width: 294, height: 26)
            container.addSubview(label)
            container.addSubview(field)
            fields.append(field)
        }

        alert.accessoryView = container
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = fields[0]

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = fields[0].stringValue.trimmingCharacters(in: .whitespaces)
        let host = fields[1].stringValue.trimmingCharacters(in: .whitespaces)
        let user = fields[2].stringValue.trimmingCharacters(in: .whitespaces)
        let pass = fields[3].stringValue
        guard !name.isEmpty, !host.isEmpty, !user.isEmpty, !pass.isEmpty else { NSSound.beep(); return }

        var server = existing ?? ServerConfig(name: name, host: host, username: user, password: pass)
        server.name = name; server.host = host; server.username = user; server.password = pass
        Store.shared.upsertServer(server)
        reloadServers()
        // 添加后立即检查一次
        check(server: server)
    }

    // MARK: - 采集

    @objc private func checkAll() {
        let servers = Store.shared.servers.filter { $0.enabled }
        guard !servers.isEmpty else { NSSound.beep(); return }
        checkBtn.title = "检查中…"
        isChecking = true
        let group = DispatchGroup()
        for server in servers {
            group.enter()
            ServerMonitor.shared.collect(server: server) { status in
                Store.shared.record(serverStatus: status)
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isChecking = false
            self?.checkBtn.title = "立即检查全部"
            self?.reloadServers()
        }
    }

    private func check(server: ServerConfig) {
        ServerMonitor.shared.collect(server: server) { [weak self] status in
            DispatchQueue.main.async {
                Store.shared.record(serverStatus: status)
                self?.reloadServers()
            }
        }
    }

    // MARK: - 导出 CSV

    @objc private func exportCSV() {
        let servers = Store.shared.servers
        guard !servers.isEmpty else {
            let a = NSAlert(); a.messageText = "没有可导出的服务器"; a.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true); a.runModal()
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "导出 \(servers.count) 台服务器配置？"
        confirm.informativeText = "CSV 包含密码明文，请妥善保管！"
        confirm.addButton(withTitle: "导出")
        confirm.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSSavePanel()
        panel.title = "导出服务器列表"
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "servers_\(df.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "名称,主机,用户名,密码\n"
        for s in servers {
            csv += "\"\(s.name.replacingOccurrences(of: "\"", with: "\"\""))\","
            csv += "\"\(s.host.replacingOccurrences(of: "\"", with: "\"\""))\","
            csv += "\"\(s.username.replacingOccurrences(of: "\"", with: "\"\""))\","
            csv += "\"\(s.password.replacingOccurrences(of: "\"", with: "\"\""))\"\n"
        }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            let a = NSAlert(); a.messageText = "导出成功"; a.informativeText = url.path; a.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true); a.runModal()
        } catch {
            let a = NSAlert(); a.messageText = "导出失败：\(error.localizedDescription)"; a.addButton(withTitle: "好")
            NSApp.activate(ignoringOtherApps: true); a.runModal()
        }
    }
}
