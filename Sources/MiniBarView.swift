import AppKit

/// 迷你进度条（纯 CoreGraphics 自绘，5-6px 圆角条）
final class MiniBarView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var barColor: NSColor = .systemGreen { didSet { needsDisplay = true } }
    var trackColor: NSColor = .quaternaryLabelColor

    override func draw(_ dirtyRect: NSRect) {
        let h: CGFloat = min(6, bounds.height)
        let y = (bounds.height - h) / 2
        trackColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: bounds.width, height: h),
                     xRadius: h / 2, yRadius: h / 2).fill()
        let w = bounds.width * CGFloat(min(max(value, 0), 100) / 100)
        if w > 0.5 {
            barColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: y, width: w, height: h),
                         xRadius: h / 2, yRadius: h / 2).fill()
        }
    }

    /// 内存分级：<75 绿 / 75-90 橙 / >=90 红
    static func memColor(_ p: Double) -> NSColor {
        p >= 90 ? .systemRed : (p >= 75 ? .systemOrange : .systemGreen)
    }

    /// 磁盘分级：<70 绿 / 70-85 橙 / >=85 红
    static func diskColor(_ p: Double) -> NSColor {
        p >= 85 ? .systemRed : (p >= 70 ? .systemOrange : .systemGreen)
    }
}
