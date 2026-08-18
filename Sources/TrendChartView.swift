import AppKit

/// 轻量趋势折线图（CoreGraphics 自绘，无第三方依赖）
final class TrendChartView: NSView {

    struct Series {
        let label: String
        let color: NSColor
        let values: [Double]
    }

    var series: [Series] = [] {
        didSet { needsDisplay = true }
    }
    var yMax: Double = 100
    var xLabels: [String] = []   // 首尾时间标签

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        guard bounds.width > 60, bounds.height > 50 else { return }

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        let padL: CGFloat = 36, padR: CGFloat = 10, padT: CGFloat = 16, padB: CGFloat = 18
        let plotW = bounds.width - padL - padR
        let plotH = bounds.height - padT - padB
        guard plotW > 20, plotH > 20 else { return }

        // 网格 + Y 轴标签（0/25/50/75/100）
        for i in 0...4 {
            let y = padT + plotH * CGFloat(i) / 4
            let path = NSBezierPath()
            path.move(to: NSPoint(x: padL, y: y))
            path.line(to: NSPoint(x: padL + plotW, y: y))
            NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 0.5
            path.stroke()

            let label = "\(Int(yMax - Double(i) * yMax / 4))"
            (label as NSString).draw(at: NSPoint(x: 4, y: y - 6),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 9),
                                                     .foregroundColor: NSColor.secondaryLabelColor])
        }

        // X 轴标签（首/尾）
        if xLabels.count >= 2 {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9),
                                                        .foregroundColor: NSColor.tertiaryLabelColor]
            (xLabels[0] as NSString).draw(at: NSPoint(x: padL, y: 2), withAttributes: attrs)
            let lastW = (xLabels[xLabels.count - 1] as NSString).size(withAttributes: attrs).width
            (xLabels[xLabels.count - 1] as NSString).draw(at: NSPoint(x: padL + plotW - lastW, y: 2), withAttributes: attrs)
        }

        // 各 series 折线
        for s in series {
            guard s.values.count >= 2 else { continue }
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineJoinStyle = .round
            for (i, v) in s.values.enumerated() {
                let x = padL + plotW * CGFloat(i) / CGFloat(s.values.count - 1)
                let clamped = min(max(v, 0), yMax)
                let y = padT + plotH * CGFloat(clamped / yMax)
                if i == 0 {
                    path.move(to: NSPoint(x: x, y: y))
                } else {
                    path.line(to: NSPoint(x: x, y: y))
                }
            }
            s.color.setStroke()
            path.stroke()

            // 末尾端点圆点
            if let last = s.values.last {
                let x = padL + plotW
                let clamped = min(max(last, 0), yMax)
                let y = padT + plotH * CGFloat(clamped / yMax)
                s.color.setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 3, y: y - 3, width: 6, height: 6)).fill()
                s.color.withAlphaComponent(0.15).setFill()
                NSBezierPath(ovalIn: NSRect(x: x - 6, y: y - 6, width: 12, height: 12)).fill()
            }
        }

        // 图例（右上角）
        var lx = padL
        for s in series {
            s.color.setFill()
            NSRect(x: lx, y: bounds.height - 12, width: 9, height: 9).fill()
            let label = s.label as NSString
            let labelSize = label.size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)])
            (label as NSString).draw(at: NSPoint(x: lx + 11, y: bounds.height - 14),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 10),
                                                     .foregroundColor: NSColor.secondaryLabelColor])
            lx += 11 + labelSize.width + 14
        }
    }
}
