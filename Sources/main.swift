import AppKit

// 入口：创建 NSApplication，挂载 AppDelegate 后进入主循环
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
