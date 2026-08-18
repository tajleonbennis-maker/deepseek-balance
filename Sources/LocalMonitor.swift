import Foundation

/// 本机 Mac 状态采集：CPU / 内存 / 磁盘 / 内存占用 Top5 应用 / CPU 型号频率与热状态（纯系统命令，无第三方依赖）
struct LocalStatus {
    var timestamp: Date = Date()
    var memPercent: Double = 0
    var cpuPercent: Double = 0
    var diskPercent: Double = 0
    var topProcesses: [(name: String, memGB: Double)] = []
    var cpuBrand: String = ""
    var cpuFreqGHz: Double = 0
    var thermalLevel: Double = 0        // machdep.xcpm.cpu_thermal_level（0-127，越高越热）
    var speedLimit: Double = 100        // CPU_Speed_Limit（100=满速，<100 说明降频发热）
}

final class LocalMonitor {

    static let shared = LocalMonitor()

    private init() {}

    /// 采集本机状态
    func collect(completion: @escaping (LocalStatus) -> Void) {
        let script = """
        echo "===MEM==="; vm_stat; sysctl -n hw.memsize
        echo "===CPU==="; top -l 2 -n 0 -s 1 | grep "CPU usage" | tail -1
        echo "===CPUINFO==="; sysctl -n machdep.cpu.brand_string; sysctl -n hw.cpufrequency; sysctl -n machdep.xcpm.cpu_thermal_level 2>/dev/null; pmset -g therm 2>/dev/null | grep CPU_Speed_Limit
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
        var totalMemBytes: Double = 0
        // Activity Monitor 口径：已使用 ≈ active + wired + compressed（不含可回收缓存）
        var pagesActive: Double = 0
        var pagesWired: Double = 0
        var pagesCompressed: Double = 0

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
                    } else if line.hasPrefix("Pages active:") {
                        pagesActive = num(from: line)
                    } else if line.hasPrefix("Pages wired down:") {
                        pagesWired = num(from: line)
                    } else if line.hasPrefix("Pages occupied by compressor:") {
                        pagesCompressed = num(from: line)
                    } else if Double(line.trimmingCharacters(in: .whitespaces)) != nil, totalMemBytes == 0 {
                        totalMemBytes = Double(line.trimmingCharacters(in: .whitespaces)) ?? 0
                    }
                }
            } else if head.contains("CPUINFO") {
                // 行1: brand_string；行2: hw.cpufrequency；行3: thermal_level；行4: CPU_Speed_Limit
                var idx = 0
                for line in lines.dropFirst() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if idx == 0 {
                        st.cpuBrand = t
                    } else if idx == 1 {
                        st.cpuFreqGHz = (Double(t) ?? 0) / 1_000_000_000
                    } else if idx == 2, let v = Double(t) {
                        st.thermalLevel = v
                    } else if t.hasPrefix("CPU_Speed_Limit"), let eq = t.split(separator: "=").last {
                        st.speedLimit = Double(eq.trimmingCharacters(in: .whitespaces)) ?? 100
                    }
                    idx += 1
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

        // 已使用 = (active + wired + compressed) × pageSize，与 Activity Monitor「已使用」对齐
        if totalMemBytes > 0 {
            let usedBytes = (pagesActive + pagesWired + pagesCompressed) * pageSize
            st.memPercent = min(100, max(0, usedBytes / totalMemBytes * 100))
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
