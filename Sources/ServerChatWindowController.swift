import AppKit

/// 服务器助手：自然语言 → DeepSeek 生成命令 → SSH 执行 → 结果回传 DeepSeek 分析（多轮对话）；执行过的查询自动记忆为「常用查询」
final class ServerChatWindowController: NSWindowController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    static let shared = ServerChatWindowController()

    // UI
    private let serverPopup = NSPopUpButton()
    private let chatScroll = NSScrollView()
    private let chatView = NSTextView()
    private let cmdTitle = NSTextField(labelWithString: "待执行命令（由 DeepSeek 生成，确认后点执行）：")
    private let cmdScroll = NSScrollView()
    private let cmdView = NSTextView()
    private let execBtn = NSButton(title: "▶ 执行命令", target: nil, action: nil)
    private let autoExecCheck = NSButton(checkboxWithTitle: "自动执行（有风险，慎用）", target: nil, action: nil)
    private let inputField = NSTextField()
    private let sendBtn = NSButton(title: "发送", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    // 常用查询面板
    private let queryTitle = NSTextField(labelWithString: "常用查询（执行过的命令已自动记忆，双击直接执行）：")
    private let queryTable = NSTableView()
    private let queryScroll = NSScrollView()
    private let delQueryBtn = NSButton(title: "删除选中", target: nil, action: nil)

    // 状态
    private var messages: [ChatMessage] = []
    private var pendingCommands: [String] = []
    private var isBusy = false
    private var sessionId = UUID().uuidString
    private var sessionStartedAt = Date()
    private var sessionServerName = ""
    private var lastUserText = ""   // 最近一次用户提问（用于自动保存常用查询）

    private let systemPrompt = """
    你是服务器运维助手。用户会描述想在远程 Linux 服务器上做的操作（查看文件、查日志、看服务状态、排查问题、部署等）。
    你必须只回复严格的 JSON（不要输出任何 JSON 以外的文字），格式：
    {"explanation": "简要说明你的思路", "commands": ["shell命令1", "shell命令2"]}
    要求：
    - commands 是要在服务器上执行的 shell 命令，尽量用只读命令排查，谨慎使用破坏性命令（rm、dd、kill -9、iptables 等）
    - 如果用户请求需要多步，拆成多个命令
    - 之后用户会把命令执行结果发给你，你要分析结果并给出下一步建议，仍然只回 JSON
    """

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "服务器助手（DeepSeek 驱动）"
        super.init(window: window)
        window.delegate = self
        buildUI()
        reloadServers()
        reloadQueries()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    /// 打开 AI 助手并选中指定服务器（供总览卡片"AI"按钮调用）
    static func show(serverId: String) {
        let vc = ServerChatWindowController.shared
        vc.reloadServers()
        let servers = Store.shared.servers.filter { $0.enabled }
        if let idx = servers.firstIndex(where: { $0.id == serverId }) {
            vc.serverPopup.selectItem(at: idx)
            vc.sessionId = UUID().uuidString
            vc.sessionStartedAt = Date()
            vc.messages.removeAll()
            vc.chatView.string = ""
            vc.cmdView.string = ""
            vc.pendingCommands = []
            vc.clearChat()
        }
        vc.showWindow(nil)
    }

    override func showWindow(_ sender: Any?) {
        reloadServers()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        // 自动让输入框获焦，光标直接在那里，可直接打字
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self?.inputField)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let W: CGFloat = 780

        // 顶部：服务器选择
        let srvLabel = NSTextField(labelWithString: "目标服务器：")
        srvLabel.frame = NSRect(x: 16, y: 658, width: 80, height: 22)
        serverPopup.frame = NSRect(x: 100, y: 658, width: 280, height: 26)
        serverPopup.target = self
        serverPopup.action = #selector(serverChanged)

        let clearBtn = NSButton(title: "清空对话", target: nil, action: nil)
        clearBtn.bezelStyle = .rounded
        clearBtn.frame = NSRect(x: W - 16 - 110, y: 658, width: 110, height: 26)
        clearBtn.target = self
        clearBtn.action = #selector(clearChat)

        content.addSubview(srvLabel)
        content.addSubview(serverPopup)
        content.addSubview(clearBtn)

        // 对话区
        chatScroll.frame = NSRect(x: 16, y: 340, width: W - 32, height: 310)
        chatScroll.hasVerticalScroller = true
        chatScroll.borderType = .bezelBorder
        chatView.isEditable = false
        chatView.isRichText = true
        chatView.font = NSFont.systemFont(ofSize: 12)
        chatView.textContainerInset = NSSize(width: 8, height: 8)
        chatView.autoresizingMask = [.width]
        chatScroll.documentView = chatView
        content.addSubview(chatScroll)

        // 命令区（左）＋ 常用查询（右）
        cmdTitle.font = NSFont.systemFont(ofSize: 11)
        cmdTitle.textColor = .secondaryLabelColor
        cmdTitle.frame = NSRect(x: 16, y: 312, width: 470, height: 18)
        queryTitle.font = NSFont.systemFont(ofSize: 11)
        queryTitle.textColor = .secondaryLabelColor
        queryTitle.frame = NSRect(x: 510, y: 312, width: 254, height: 18)
        content.addSubview(cmdTitle)
        content.addSubview(queryTitle)

        cmdScroll.frame = NSRect(x: 16, y: 200, width: 470, height: 106)
        cmdScroll.hasVerticalScroller = true
        cmdScroll.borderType = .bezelBorder
        cmdView.isEditable = false
        cmdView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        cmdView.textContainerInset = NSSize(width: 8, height: 8)
        cmdView.autoresizingMask = [.width]
        cmdScroll.documentView = cmdView
        content.addSubview(cmdScroll)

        queryTable.dataSource = self
        queryTable.delegate = self
        queryTable.rowHeight = 24
        queryTable.usesAlternatingRowBackgroundColors = true
        queryTable.doubleAction = #selector(queryDoubleClicked)
        let qc1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("qtitle"))
        qc1.title = "查询（双击执行）"
        qc1.width = 160
        let qc2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("qcount"))
        qc2.title = "次"
        qc2.width = 40
        queryTable.addTableColumn(qc1)
        queryTable.addTableColumn(qc2)
        queryScroll.frame = NSRect(x: 510, y: 200, width: 254, height: 106)
        queryScroll.hasVerticalScroller = true
        queryScroll.borderType = .bezelBorder
        queryScroll.documentView = queryTable
        content.addSubview(queryScroll)

        // 执行区
        execBtn.bezelStyle = .rounded
        execBtn.target = self
        execBtn.action = #selector(execPending)
        execBtn.frame = NSRect(x: 16, y: 164, width: 130, height: 28)
        autoExecCheck.frame = NSRect(x: 156, y: 166, width: 240, height: 22)
        delQueryBtn.bezelStyle = .rounded
        delQueryBtn.target = self
        delQueryBtn.action = #selector(delQueryAction)
        delQueryBtn.frame = NSRect(x: 510, y: 164, width: 100, height: 28)
        content.addSubview(execBtn)
        content.addSubview(autoExecCheck)
        content.addSubview(delQueryBtn)

        // 输入区
        inputField.placeholderString = "输入你想做的事，例如：查看 /opt/deeptutor 目录结构、看 nginx 日志最近的报错…"
        inputField.frame = NSRect(x: 16, y: 110, width: W - 32 - 120, height: 28)
        inputField.target = self
        inputField.action = #selector(sendAction)
        inputField.delegate = self
        sendBtn.bezelStyle = .rounded
        sendBtn.keyEquivalent = "\r"
        sendBtn.target = self
        sendBtn.action = #selector(sendAction)
        sendBtn.frame = NSRect(x: W - 16 - 110, y: 110, width: 110, height: 28)
        content.addSubview(inputField)
        content.addSubview(sendBtn)

        // 状态
        statusLabel.font = NSFont.systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.frame = NSRect(x: 16, y: 76, width: W - 32, height: 16)
        content.addSubview(statusLabel)
    }

    private func reloadServers() {
        let selected = selectedServer()?.id
        serverPopup.removeAllItems()
        let servers = Store.shared.servers.filter { $0.enabled }
        if servers.isEmpty {
            serverPopup.addItem(withTitle: "（请先在「服务器管理」添加服务器）")
        }
        for s in servers {
            serverPopup.addItem(withTitle: "\(s.name)（\(s.host)）")
            serverPopup.lastItem?.representedObject = s.id
        }
        if let sel = selected {
            for (i, s) in servers.enumerated() where s.id == sel {
                serverPopup.selectItem(at: i)
            }
        }
    }

    private func selectedServer() -> ServerConfig? {
        guard let sid = serverPopup.selectedItem?.representedObject as? String else { return nil }
        return Store.shared.servers.first { $0.id == sid }
    }

    private func activeAPIKey() -> String? {
        Store.shared.config.keys.first { $0.enabled }?.apiKey
    }

    // MARK: - 对话

    @objc private func sendAction() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let server = selectedServer(), let apiKey = activeAPIKey() else {
            appendChat("⚠️ 请先在「服务器管理」添加服务器，并在「设置」中添加 DeepSeek API Key", color: .systemRed)
            return
        }
        guard !isBusy else { return }

        inputField.stringValue = ""
        lastUserText = text
        appendChat("🧑 我（\(server.name)）：\n\(text)", color: .labelColor)
        messages.append(ChatMessage(role: "user", content: text))
        logEntry(role: "user", content: text, server: server)
        askDeepSeek()
    }

    /// 追加一条会话日志并持久化
    private func logEntry(role: String, content: String, server: ServerConfig?) {
        sessionServerName = server?.name ?? sessionServerName
        var entries = Store.shared.chatLogs.first { $0.id == sessionId }?.entries ?? []
        entries.append(ChatLogEntry(role: role, content: content))
        Store.shared.upsertChatLog(ChatLog(id: sessionId, timestamp: sessionStartedAt,
                                           serverId: server?.id ?? "", serverName: sessionServerName, entries: entries))
    }

    private func askDeepSeek() {
        guard let apiKey = activeAPIKey() else { return }
        isBusy = true
        statusLabel.stringValue = "DeepSeek 思考中…"
        sendBtn.isEnabled = false
        execBtn.isEnabled = false

        var full = [ChatMessage(role: "system", content: systemPrompt)]
        full.append(contentsOf: messages)

        DeepSeekChatClient.shared.chat(apiKey: apiKey, messages: full) { [weak self] reply, error in
            guard let self = self else { return }
            self.isBusy = false
            self.sendBtn.isEnabled = true
            self.execBtn.isEnabled = true

            guard let reply = reply else {
                self.statusLabel.stringValue = "DeepSeek 调用失败：\(error ?? "未知错误")"
                return
            }
            self.statusLabel.stringValue = "就绪"
            self.messages.append(ChatMessage(role: "assistant", content: reply))
            self.logEntry(role: "assistant", content: reply, server: self.selectedServer())

            let parsed = Self.parseCommands(from: reply)
            self.appendChat("🤖 DeepSeek：\n\(parsed.explanation.isEmpty ? reply : parsed.explanation)", color: .systemBlue)

            if !parsed.commands.isEmpty {
                self.pendingCommands = parsed.commands
                self.cmdView.string = parsed.commands.enumerated().map { "\($0.offset + 1). $ \($0.element)" }.joined(separator: "\n")
                self.appendChat("🔧 建议执行命令：\n" + parsed.commands.map { "$ \($0)" }.joined(separator: "\n"), color: .systemOrange)
                if self.autoExecCheck.state == .on {
                    self.execPending()
                } else {
                    self.statusLabel.stringValue = "DeepSeek 生成了 \(parsed.commands.count) 条命令，确认后点「执行命令」"
                }
            }
        }
    }

    @objc private func execPending() {
        guard !isBusy else { return }
        guard let server = selectedServer() else { return }
        let cmds = pendingCommands
        guard !cmds.isEmpty else { NSSound.beep(); return }
        pendingCommands = []

        appendChat("📤 正在执行 \(cmds.count) 条命令于 \(server.name)：\n" + cmds.map { "$ \($0)" }.joined(separator: "\n"), color: .systemBlue)
        cmdView.string = ""
        isBusy = true
        statusLabel.stringValue = "命令执行中…"
        execBtn.isEnabled = false

        var results: [String] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for c in cmds {
            group.enter()
            ServerMonitor.shared.execute(server: server, command: c) { out, err in
                lock.lock()
                results.append("$ \(c)\n\(out ?? err ?? "（无输出）")")
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isBusy = false
            self.execBtn.isEnabled = true
            let resultText = results.joined(separator: "\n\n")
            self.appendChat("📥 执行结果：\n\(resultText)", color: .secondaryLabelColor)
            self.statusLabel.stringValue = "已执行，正在让 DeepSeek 分析结果…"
            self.messages.append(ChatMessage(role: "user", content: "命令执行结果：\n\(resultText)"))
            self.logEntry(role: "result", content: resultText, server: server)
            // 自动记忆为常用查询（下次可直接双击执行）
            if !cmds.isEmpty, !self.lastUserText.isEmpty {
                Store.shared.upsertSavedQuery(title: self.lastUserText, serverId: server.id, commands: cmds)
                self.reloadQueries()
            }
            self.askDeepSeek()
        }
    }

    @objc private func clearChat() {
        messages.removeAll()
        pendingCommands = []
        chatView.string = ""
        cmdView.string = ""
        sessionId = UUID().uuidString
        sessionStartedAt = Date()
        statusLabel.stringValue = "已清空，开始新对话（新会话将单独归档）"
        appendChat("👋 服务器助手已就绪。描述你想在服务器上做的事，例如：\n· 查看 /opt/deeptutor 目录下有哪些文件\n· 看下 nginx 最近有没有报错\n· 磁盘快满了，帮我找出大文件", color: .secondaryLabelColor)
    }

    @objc private func serverChanged() {
        sessionId = UUID().uuidString
        sessionStartedAt = Date()
        messages.removeAll()
        chatView.string = ""
        cmdView.string = ""
        pendingCommands = []
        clearChat()
    }

    // MARK: - 常用查询

    private func reloadQueries() {
        queryTable.reloadData()
    }

    @objc private func queryDoubleClicked() {
        let row = queryTable.clickedRow
        let queries = Store.shared.savedQueries
        guard row >= 0, row < queries.count else { return }
        let q = queries[row]
        guard let server = Store.shared.servers.first(where: { $0.id == q.serverId }) else {
            appendChat("⚠️ 该查询对应的服务器已不存在", color: .systemRed)
            return
        }
        // 直接执行已保存的命令
        appendChat("⚡ 执行常用查询「\(q.title)」于 \(server.name)：\n" + q.commands.map { "$ \($0)" }.joined(separator: "\n"), color: .systemBlue)
        isBusy = true
        statusLabel.stringValue = "执行中…"
        var results: [String] = []
        let lock = NSLock()
        let group = DispatchGroup()
        for c in q.commands {
            group.enter()
            ServerMonitor.shared.execute(server: server, command: c) { out, err in
                lock.lock()
                results.append("$ \(c)\n\(out ?? err ?? "（无输出）")")
                lock.unlock()
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isBusy = false
            let resultText = results.joined(separator: "\n\n")
            self.appendChat("📥 执行结果：\n\(resultText)", color: .secondaryLabelColor)
            self.statusLabel.stringValue = "已执行常用查询「\(q.title)」"
            self.logEntry(role: "result", content: "常用查询「\(q.title)」结果：\n\(resultText)", server: server)
        }
    }

    @objc private func delQueryAction() {
        let row = queryTable.selectedRow
        let queries = Store.shared.savedQueries
        guard row >= 0, row < queries.count else { NSSound.beep(); return }
        Store.shared.removeSavedQuery(id: queries[row].id)
        reloadQueries()
    }

    // MARK: - 常用查询表格

    func numberOfRows(in tableView: NSTableView) -> Int {
        Store.shared.savedQueries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let queries = Store.shared.savedQueries
        guard row < queries.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let q = queries[row]
        let text = id == "qtitle" ? q.title : "\(q.useCount)"
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.lineBreakMode = .byTruncatingTail
        label.textColor = id == "qtitle" ? .labelColor : .secondaryLabelColor
        cell.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    // MARK: - 工具

    private func appendChat(_ text: String, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)]
        chatView.textStorage?.append(NSAttributedString(string: text + "\n\n", attributes: attrs))
        chatView.scrollToEndOfDocument(nil)
    }

    /// 从 DeepSeek 回复中提取 JSON 命令块
    static func parseCommands(from text: String) -> (explanation: String, commands: [String]) {
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           start < end {
            let jsonStr = String(text[start...end])
            if let data = jsonStr.data(using: .utf8),
               let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let exp = json["explanation"] as? String ?? ""
                let cmds = json["commands"] as? [String] ?? []
                return (exp, cmds)
            }
        }
        // 非 JSON：尝试把行首以 $ 开头的当作命令
        let cmds = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("$ ") }
            .map { String($0.dropFirst(2)) }
        return (text, cmds)
    }
}
