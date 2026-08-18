import Foundation

/// 本机 Mac 状态采集：CPU / 内存 / 磁盘 / 内存占用 Top5 应用（纯系统命令，无第三方依赖）
struct LocalStatus {
    var timestamp: Date = Date()
    var memPercent: Double = 0
    var cpuPercent: Double = 0
    var diskPercent: Double = 0
    var topProcesses: [(name: String, memGB: Double)] = []
}

final class LocalMonitor {

    static let shared = LocalMonitor()

    private init() {}

    /// 采集本机状态
    func collect(completion: @escaping (LocalStatus) -> Void) {
        let script = """
        echo "===MEM==="; vm_stat | head -6; sysctl -n hw.memsize; memory_pressure 2>/dev/null | grep "free percentage"
        echo "===CPU==="; top -l 1 -n 0 | grep "CPU usage"
        echo "===DISK==="; df -h / | tail -1
        echo "===PROC==="; ps -m -o comm=,rss= -c | head -6
        """
        run(script: script) { output, _ in
            guard let output = output, !output.isEmpty else {
                completion(LocalStatus())
                return
            }
            completion(Self.parse(output))
        }
    }

    private func run(script: String, completion: @escaping (String?, String?) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            completion(nil, error.localizedDescription)
            return
        }
        process.waitUntilExit()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        if process.terminationStatus == 0, let out = out, !out.isEmpty {
            completion(out, nil)
        } else {
            completion(out?.isEmpty == false ? out : nil, err)
        }
    }

    // MARK: - 解析

    static func parse(_ raw: String) -> LocalStatus {
        var st = LocalStatus()
        var pageSize: Double = 4096
        var pagesFree: Double = 0
        var totalMemBytes: Double = 0
        var memFreePercent: Double = -1   // memory_pressure 官方口径

        let sections = raw.components(separatedBy: "\n===")
        for section in sections {
            let lines = section.components(separatedBy: "\n")
            guard let head = lines.first else { continue }
            if head.contains("MEM") {
                for line in lines {
                    if line.contains("page size of") {
                        let parts = line.split(separator: " ")
                        if let idx = parts.firstIndex(where: { $0 == "of" }), idx + 1 < parts.count {
                            pageSize = Double(parts[idx + 1].replacingOccurrences(of: "bytes", with: "").replacingOccurrences(of: ".", with: "")) ?? 4096
                        }
                    } else if line.hasPrefix("Pages free:") {
                        pagesFree = num(from: line)
                    } else if line.contains("free percentage") {
                        // System-wide memory free percentage: 75%
                        if let n = line.split(separator: ":").last?
                            .trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "%", with: "") {
                            memFreePercent = Double(n) ?? -1
                        }
                    } else if Double(line.trimmingCharacters(in: .whitespaces)) != nil, totalMemBytes == 0 {
                        totalMemBytes = Double(line.trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
            } else if head.contains("CPU") {
                if let line = lines.first(where: { $0.hasPrefix("CPU usage:") }) {
                    // CPU usage: 8.4% user, 12.5% sys, 79.0% idle
                    let nums = line.split(separator: "%").compactMap { seg in
                        Double(seg.split(separator: ",").last?.trimmingCharacters(in: .whitespaces) ?? "")
                    }
                    if nums.count >= 3 {
                        st.cpuPercent = nums[0] + nums[1]
                    }
                }
            } else if head.contains("DISK") {
                if let diskLine = lines.first(where: { $0.hasPrefix("/dev/") }) {
                    let f = diskLine.split(separator: " ").map(String.init)
                    if f.count >= 5 {
                        st.diskPercent = Double(f[4].replacingOccurrences(of: "%", with: "")) ?? 0
                    }
                }
            } else if head.contains("PROC") {
                var procs: [(String, Double)] = []
                for line in lines.dropFirst() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let f = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
                    if f.count == 2, let rssKB = Double(f[1]) {
                        procs.append((f[0], rssKB / 1024 / 1024))  // KB → GB
                    }
                }
                st.topProcesses = Array(procs.prefix(5))
            }
        }

        // 内存：优先 memory_pressure 官方口径；失败则用 vm_stat 估算
        if memFreePercent >= 0 {
            st.memPercent = min(100, max(0, 100 - memFreePercent))
        } else if totalMemBytes > 0 {
            let freeBytes = pagesFree * pageSize
            st.memPercent = min(100, max(0, (totalMemBytes - freeBytes) / totalMemBytes * 100))
        }
        return st
    }

    private static func num(from line: String) -> Double {
        let s = line.split(separator: ":").last?
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces) ?? "0"
        return Double(s) ?? 0
    }
}
