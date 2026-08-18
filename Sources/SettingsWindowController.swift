import AppKit
import UniformTypeIdentifiers

/// 设置窗口：管理多个 DeepSeek API Key + 刷新/提醒/告警选项
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {

    private let onChange: () -> Void

    // 表格与按钮
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let addBtn = NSButton()
    private let editBtn = NSButton()
    private let delBtn = NSButton()
    private let exportBtn = NSButton()
    private let exportSelectedBtn = NSButton()

    // 选项区
    private let refreshPopup = NSPopUpButton()
    private let alertCheck = NSButton(checkboxWithTitle: "余额低于阈值时提醒", target: nil, action: nil)
    private let thresholdField = NSTextField()
    private let spikeCheck = NSButton(checkboxWithTitle: "单次轮询消耗超过", target: nil, action: nil)
    private let spikeThresholdField = NSTextField()
    private let spikeUnit = NSTextField(labelWithString: "元（可改）")
    private let rateCheck = NSButton(checkboxWithTitle: "消耗速率超过", target: nil, action: nil)
    private let rateThresholdField = NSTextField()
    private let rateUnit = NSTextField(labelWithString: "元 / 分钟（可改）")

    private let settingsBox = NSBox()
    private let openDataBtn = NSButton()
    private let saveBtn = NSButton(title: "保存并关闭", target: nil, action: nil)
    private let notifStatusLabel = NSTextField(labelWithString: "通知权限：检查中…")
    private let notifBtn = NSButton(title: "打开系统设置", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "数据仅存本地：~/Library/Application Support/DeepSeekBalance/")
    private let onChangeLabel = NSTextField(labelWithString: "金额阈值可随时改：点击输入框，直接输入数字，回车保存")

    private weak var pendingKeyField: NSTextField?

    // 固定窗口尺寸
    private let winW: CGFloat = 640
    private let winH: CGFloat = 540

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "DeepSeek 余额监控 · 设置"
        super.init(window: window)
        window.delegate = self
        buildUI()
        reloadData()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override func showWindow(_ sender: Any?) {
        reloadData()
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        applyControlsToConfig()
        Store.shared.save()
        onChange()
        sender.orderOut(nil)
        return false
    }

    // MARK: - 纯 frame 布局（避免 Auto Layout 塌陷）

    private func buildUI() {
        guard let content = window?.contentView else { return }
        let margin: CGFloat = 16

        // ---- 表格 ----
        let tableTop = winH - margin - 230
        scrollView.frame = NSRect(x: margin, y: tableTop, width: winW - 2*margin, height: 230)
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.autoresizingMask = []

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 26
        tableView.allowsColumnReordering = false
        tableView.allowsMultipleSelection = true   // ★ 支持多选导出
        tableView.usesAlternatingRowBackgroundColors = true

        let cols: [(String, CGFloat)] = [("name", 110), ("balance", 80), ("status", 70), ("key", 220), ("enabled", 50)]
        for (id, w) in cols {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = id == "name" ? "名称" : (id == "balance" ? "余额" : (id == "status" ? "状态" : (id == "key" ? "API Key" : "启用")))
            col.width = w
            tableView.addTableColumn(col)
        }
        scrollView.documentView = tableView
        content.addSubview(scrollView)

        // ---- 按钮行（表格下方）----
        let btnY = tableTop - 10 - 28
        addBtn.title = "＋ 添加 Key";          addBtn.bezelStyle = .rounded;  addBtn.target = self;  addBtn.action = #selector(addKey)
        editBtn.title = "编辑";                  editBtn.bezelStyle = .rounded; editBtn.target = self; editBtn.action = #selector(editKey)
        delBtn.title = "删除";                   delBtn.bezelStyle = .rounded;  delBtn.target = self;  delBtn.action = #selector(deleteKey)
        exportBtn.title = "导出全部 Key";        exportBtn.bezelStyle = .rounded;  exportBtn.target = self;  exportBtn.action = #selector(exportAllKeys)
        exportSelectedBtn.title = "导出选中";    exportSelectedBtn.bezelStyle = .rounded;  exportSelectedBtn.target = self;  exportSelectedBtn.action = #selector(exportSelectedKeys)

        addBtn.frame = NSRect(x: margin, y: btnY, width: 96, height: 28)
        editBtn.frame = NSRect(x: margin + 104, y: btnY, width: 60, height: 28)
        delBtn.frame = NSRect(x: margin + 172, y: btnY, width: 60, height: 28)
        exportBtn.frame = NSRect(x: winW - margin - 220, y: btnY, width: 120, height: 28)
        exportSelectedBtn.frame = NSRect(x: winW - margin - 92, y: btnY, width: 92, height: 28)

        for v in [addBtn, editBtn, delBtn, exportBtn, exportSelectedBtn] {
            v.translatesAutoresizingMaskIntoConstraints = true
            content.addSubview(v)
        }

        // ---- 选项区（NSBox）----
        let boxH: CGFloat = 190
        let boxY = btnY - 14 - boxH
        settingsBox.frame = NSRect(x: margin, y: boxY, width: winW - 2*margin, height: boxH)
        settingsBox.title = " 告警与刷新 "
        settingsBox.boxType = .primary
        settingsBox.translatesAutoresizingMaskIntoConstraints = true
        content.addSubview(settingsBox)

        // ---- box 内子视图（contentView 内 frame 布局）----
        let bc = settingsBox.contentView!
        for item in ["30 秒", "1 分钟", "2 分钟", "5 分钟", "10 分钟"] { refreshPopup.addItem(withTitle: item) }
        refreshPopup.target = self; refreshPopup.action = #selector(popupChanged)
        alertCheck.target = self;     alertCheck.action = #selector(alertToggled)
        thresholdField.placeholderString = "10"; thresholdField.alignment = .right
        thresholdField.target = self; thresholdField.action = #selector(thresholdEntered)
        spikeCheck.target = self;     spikeCheck.action = #selector(spikeToggled)
        spikeThresholdField.placeholderString = "1.0"; spikeThresholdField.alignment = .right
        spikeThresholdField.target = self; spikeThresholdField.action = #selector(spikeEntered)
        rateCheck.target = self;      rateCheck.action = #selector(rateToggled)
        rateThresholdField.placeholderString = "0.5"; rateThresholdField.alignment = .right
        rateThresholdField.target = self; rateThresholdField.action = #selector(rateEntered)
        spikeUnit.textColor = .secondaryLabelColor
        rateUnit.textColor = .secondaryLabelColor
        onChangeLabel.textColor = .tertiaryLabelColor
        onChangeLabel.font = NSFont.systemFont(ofSize: 10)

        // 3 行布局（每行 36，坐标基于 box 高度 190 静态计算，避免依赖 bc.bounds）
        let rowH: CGFloat = 36
        let row1Y: CGFloat = 142   // 第 1 行控件中心 y
        let row2Y = row1Y - rowH   // 106
        let row3Y = row2Y - rowH   // 70

        // 第 1 行：自动刷新 + 余额阈值
        bc.addSubview(NSTextField.styledLabel("自动刷新间隔：", x: 12, y: row1Y, w: 120))
        refreshPopup.frame = NSRect(x: 138, y: row1Y - 3, width: 90, height: 26)
        alertCheck.frame = NSRect(x: 240, y: row1Y, width: 200, height: 22)
        thresholdField.frame = NSRect(x: 446, y: row1Y - 3, width: 60, height: 26)
        bc.addSubview(NSTextField.styledLabel("元", x: 510, y: row1Y, w: 30))
        for v in [refreshPopup, alertCheck, thresholdField] { v.translatesAutoresizingMaskIntoConstraints = true; bc.addSubview(v) }

        // 第 2 行：单次消耗
        spikeCheck.frame = NSRect(x: 12, y: row2Y, width: 200, height: 22)
        spikeThresholdField.frame = NSRect(x: 218, y: row2Y - 3, width: 60, height: 26)
        spikeUnit.frame = NSRect(x: 282, y: row2Y, width: 200, height: 22)
        for v in [spikeCheck, spikeThresholdField, spikeUnit] { v.translatesAutoresizingMaskIntoConstraints = true; bc.addSubview(v) }

        // 第 3 行：消耗速率
        rateCheck.frame = NSRect(x: 12, y: row3Y, width: 200, height: 22)
        rateThresholdField.frame = NSRect(x: 218, y: row3Y - 3, width: 60, height: 26)
        rateUnit.frame = NSRect(x: 282, y: row3Y, width: 240, height: 22)
        for v in [rateCheck, rateThresholdField, rateUnit] { v.translatesAutoresizingMaskIntoConstraints = true; bc.addSubview(v) }

        // 第 4 行：通知权限状态
        let row4Y = row3Y - rowH   // 34
        notifStatusLabel.textColor = .secondaryLabelColor
        notifStatusLabel.font = NSFont.systemFont(ofSize: 12)
        notifStatusLabel.frame = NSRect(x: 12, y: row4Y, width: 300, height: 22)
        notifBtn.bezelStyle = .rounded
        notifBtn.target = self
        notifBtn.action = #selector(openNotificationSettings)
        notifBtn.frame = NSRect(x: 320, y: row4Y - 3, width: 120, height: 24)
        for v in [notifStatusLabel, notifBtn] { v.translatesAutoresizingMaskIntoConstraints = true; bc.addSubview(v) }

        // ---- 底部 hint 与操作 ----
        let hintY = boxY - 12 - 16
        onChangeLabel.frame = NSRect(x: margin, y: hintY + 18, width: winW - 2*margin, height: 14)
        hintLabel.frame = NSRect(x: margin, y: hintY, width: winW - 2*margin, height: 16)
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        for v in [onChangeLabel, hintLabel] { v.translatesAutoresizingMaskIntoConstraints = true; content.addSubview(v) }

        let actionY = hintY - 6 - 28
        openDataBtn.title = "打开数据目录"
        openDataBtn.bezelStyle = .rounded
        openDataBtn.target = self
        openDataBtn.action = #selector(openDataDir)
        saveBtn.bezelStyle = .rounded
        saveBtn.target = self
        saveBtn.action = #selector(saveAndClose)
        openDataBtn.frame = NSRect(x: margin, y: actionY, width: 120, height: 28)
        saveBtn.frame = NSRect(x: winW - margin - 96, y: actionY, width: 96, height: 28)
        for v in [openDataBtn, saveBtn] { v.translatesAutoresizingMaskIntoConstraints = true; content.addSubview(v) }
    }

    // MARK: - 数据

    private func reloadData() {
        let cfg = Store.shared.config
        let interval = max(15, cfg.refreshInterval)
        switch interval {
        case ...40: refreshPopup.selectItem(at: 0)
        case ...90: refreshPopup.selectItem(at: 1)
        case ...150: refreshPopup.selectItem(at: 2)
        case ...360: refreshPopup.selectItem(at: 3)
        default: refreshPopup.selectItem(at: 4)
        }
        alertCheck.state = cfg.lowBalanceAlert ? .on : .off
        thresholdField.stringValue = String(format: "%.1f", cfg.alertThreshold)
        thresholdField.isEnabled = cfg.lowBalanceAlert

        spikeCheck.state = cfg.spikeAlert ? .on : .off
        spikeThresholdField.stringValue = String(format: "%.2f", cfg.spikeThreshold)
        spikeThresholdField.isEnabled = cfg.spikeAlert

        rateCheck.state = cfg.rateAlert ? .on : .off
        rateThresholdField.stringValue = String(format: "%.2f", cfg.rateThreshold)
        rateThresholdField.isEnabled = cfg.rateAlert

        // 通知权限状态（异步获取）
        AppDelegate.notificationStatus { [weak self] status, granted in
            self?.notifStatusLabel.stringValue = "通知权限：\(status)"
            self?.notifStatusLabel.textColor = granted ? .secondaryLabelColor : .systemRed
            self?.notifBtn.isHidden = granted
        }

        tableView.reloadData()
    }

    private func applyControlsToConfig() {
        let idx = refreshPopup.indexOfSelectedItem
        Store.shared.config.refreshInterval = [30, 60, 120, 300, 600][max(0, idx)]
        Store.shared.config.lowBalanceAlert = alertCheck.state == .on
        Store.shared.config.alertThreshold = max(0, parseNum(thresholdField.stringValue, default: 10))
        thresholdField.isEnabled = Store.shared.config.lowBalanceAlert

        Store.shared.config.spikeAlert = spikeCheck.state == .on
        Store.shared.config.spikeThreshold = max(0, parseNum(spikeThresholdField.stringValue, default: 1.0))
        spikeThresholdField.isEnabled = Store.shared.config.spikeAlert

        Store.shared.config.rateAlert = rateCheck.state == .on
        Store.shared.config.rateThreshold = max(0, parseNum(rateThresholdField.stringValue, default: 0.5))
        rateThresholdField.isEnabled = Store.shared.config.rateAlert
    }

    private func parseNum(_ s: String, default def: Double) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? def
    }

    // MARK: - TableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        Store.shared.config.keys.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let keys = Store.shared.config.keys
        guard row < keys.count, let id = tableColumn?.identifier else { return nil }
        let key = keys[row]
        let res = Store.shared.result(for: key.id)

        let cell = NSTableCellView()
        let text = NSTextField(labelWithString: "")
        text.font = NSFont.systemFont(ofSize: 12)
        text.lineBreakMode = .byTruncatingMiddle
        cell.addSubview(text)
        text.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        switch id.rawValue {
        case "name":
            text.stringValue = key.name
            text.textColor = key.enabled ? .labelColor : .tertiaryLabelColor
        case "balance":
            if let r = res, r.status == .ok {
                text.stringValue = StatusMenuController.fmt(r.total, r.currency)
                text.textColor = .labelColor
            } else {
                text.stringValue = "—"
                text.textColor = .tertiaryLabelColor
            }
        case "status":
            text.stringValue = res?.statusText ?? "查询中"
            if let r = res {
                text.textColor = r.status == .ok ? (r.isAvailable ? .systemGreen : .systemOrange) : .systemRed
            }
        case "key":
            text.stringValue = key.maskedKey
            text.textColor = .secondaryLabelColor
        case "enabled":
            let on = NSButton(checkboxWithTitle: "", target: nil, action: nil)
            on.state = key.enabled ? .on : .off
            on.isEnabled = false
            return on
        default:
            return nil
        }
        return cell
    }

    // MARK: - Key 增删改

    @objc private func addKey() { promptForKey(existing: nil) }

    @objc private func editKey() {
        let row = tableView.selectedRow
        guard row >= 0, row < Store.shared.config.keys.count else { NSSound.beep(); return }
        promptForKey(existing: Store.shared.config.keys[row])
    }

    @objc private func deleteKey() {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { NSSound.beep(); return }
        let confirm = NSAlert()
        confirm.messageText = "删除 \(rows.count) 个 Key？"
        confirm.informativeText = "仅移除本地配置，不影响 DeepSeek 账号。"
        confirm.addButton(withTitle: "删除")
        confirm.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        let removeSet = Set(rows)
        Store.shared.config.keys = Store.shared.config.keys.enumerated()
            .filter { !removeSet.contains($0.offset) }
            .map { $0.element }
        Store.shared.save()
        reloadData()
        onChange()
    }

    private func promptForKey(existing: KeyConfig?) {
        let alert = NSAlert()
        alert.messageText = existing == nil ? "添加 DeepSeek API Key" : "编辑 API Key"
        alert.informativeText = "粘贴 DeepSeek 开放平台的 API Key（sk-…），名称自动生成。"

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 64))
        let keyLabel = NSTextField(labelWithString: "API Key")
        keyLabel.frame = NSRect(x: 0, y: 44, width: 340, height: 16)
        let keyField = NSSecureTextField(string: existing?.apiKey ?? "")
        keyField.frame = NSRect(x: 0, y: 16, width: 340, height: 26)
        keyField.placeholderString = "sk-…"
        let showCheck = NSButton(checkboxWithTitle: "显示密钥明文", target: nil, action: nil)
        showCheck.frame = NSRect(x: 0, y: 0, width: 140, height: 14)
        showCheck.state = .off
        showCheck.target = self
        showCheck.action = #selector(toggleKeyVisibility(_:))
        pendingKeyField = keyField

        container.addSubview(keyLabel)
        container.addSubview(keyField)
        container.addSubview(showCheck)

        alert.accessoryView = container
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = keyField

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let key = (pendingKeyField?.stringValue ?? "").trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { NSSound.beep(); return }
            if var k = existing {
                k.apiKey = key
                if let idx = Store.shared.config.keys.firstIndex(where: { $0.id == k.id }) {
                    Store.shared.config.keys[idx] = k
                }
            } else {
                let autoName = "账号 \(Store.shared.config.keys.count + 1)"
                Store.shared.config.keys.append(KeyConfig(name: autoName, apiKey: key))
            }
            Store.shared.save()
            reloadData()
            onChange()
        }
    }

    @objc private func toggleKeyVisibility(_ sender: NSButton) {
        guard let current = pendingKeyField, let container = current.superview else { return }
        let value = current.stringValue
        let newField: NSTextField
        if sender.state == .on {
            newField = NSTextField(string: value)
        } else {
            newField = NSSecureTextField(string: value)
        }
        newField.frame = current.frame
        newField.placeholderString = "sk-…"
        current.removeFromSuperview()
        container.addSubview(newField)
        pendingKeyField = newField
    }

    // MARK: - Actions

    @objc private func popupChanged() { applyControlsToConfig(); Store.shared.save() }
    @objc private func alertToggled() { thresholdField.isEnabled = alertCheck.state == .on; applyControlsToConfig(); Store.shared.save() }
    @objc private func thresholdEntered() { applyControlsToConfig(); Store.shared.save() }
    @objc private func spikeToggled() { spikeThresholdField.isEnabled = spikeCheck.state == .on; applyControlsToConfig(); Store.shared.save() }
    @objc private func spikeEntered() { applyControlsToConfig(); Store.shared.save() }
    @objc private func rateToggled() { rateThresholdField.isEnabled = rateCheck.state == .on; applyControlsToConfig(); Store.shared.save() }
    @objc private func rateEntered() { applyControlsToConfig(); Store.shared.save() }

    @objc private func saveAndClose() { window?.performClose(nil) }
    @objc private func openDataDir() { NSWorkspace.shared.open(Store.shared.dataDirectory) }

    @objc private func openNotificationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
    }

    // MARK: - 导出（全部 / 选中）

    @objc private func exportAllKeys() {
        let keys = Store.shared.config.keys
        guard !keys.isEmpty else { alertInfo("没有可导出的 Key", "请先添加至少一个 API Key。"); return }
        performExport(keys: keys, scope: "全部")
    }

    @objc private func exportSelectedKeys() {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else {
            alertInfo("未选中任何 Key", "请先在表格里按住 ⌘ / Shift 多选 Key，再点导出。")
            return
        }
        let keys = rows.compactMap { Store.shared.config.keys[safe: $0] }
        performExport(keys: keys, scope: "选中")
    }

    private func performExport(keys: [KeyConfig], scope: String) {
        let confirm = NSAlert()
        confirm.messageText = "导出\(scope)的 \(keys.count) 个 API Key？"
        confirm.informativeText = "导出的 CSV 包含密钥明文，请妥善保管，不要分享或提交到代码仓库。"
        confirm.addButton(withTitle: "导出")
        confirm.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let panel = NSSavePanel()
        panel.title = "导出 DeepSeek API Key"
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "deepseek_keys_\(scope)_\(df.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "名称,API Key\n"
        for k in keys {
            let name = k.name.replacingOccurrences(of: "\"", with: "\"\"")
            let key = k.apiKey.replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\"\(name)\",\"\(key)\"\n"
        }
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            alertInfo("导出成功", "已保存到：\n\(url.path)")
        } catch {
            alertInfo("导出失败", error.localizedDescription)
        }
    }

    private func alertInfo(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

// MARK: - 小工具

private extension NSTextField {
    static func styledLabel(_ text: String, x: CGFloat, y: CGFloat, w: CGFloat) -> NSTextField {
        let tf = NSTextField(labelWithString: text)
        tf.frame = NSRect(x: x, y: y, width: w, height: 22)
        tf.translatesAutoresizingMaskIntoConstraints = true
        return tf
    }
}

private extension Array {
    subscript(safe idx: Int) -> Element? {
        indices.contains(idx) ? self[idx] : nil
    }
}

extension AppConfig {
    subscript(keyId: String) -> KeyConfig? {
        keys.first(where: { $0.id == keyId })
    }
}
