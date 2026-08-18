import Foundation

/// 服务器健康采集器：通过 SSH（SSH_ASKPASS 自动填充密码）执行系统命令，解析内存/CPU/磁盘/进程/登录记录
final class ServerMonitor {

    static let shared = ServerMonitor()

    private let sshPath = "/usr/bin/ssh"

    private init() {}

    /// 供服务器助手对话使用的公共执行接口
    func execute(server: ServerConfig, command: String, completion: @escaping (String?, String?) -> Void) {
        runSSH(server: server, command: command, completion: completion)
    }

    /// 采集单台服务器
    func collect(server: ServerConfig, completion: @escaping (ServerStatus) -> Void) {
        let script = """
        echo "===MEM==="; LC_ALL=C free -m | head -3
        echo "===LOAD==="; uptime
        echo "===DISK==="; LC_ALL=C df -h / | tail -1
        echo "===PROC==="; LC_ALL=C ps -eo pid,user,pmem,pcpu,comm,args --sort=-pmem | head -10
        echo "===LAST==="; LC_ALL=C last -n 8 2>/dev/null | grep -v '^$' | grep -v 'wtmp begins' | head -8
        """

        runSSH(server: server, command: script) { output, error in
            guard let output = output, !output.isEmpty else {
                var st = ServerStatus(serverId: server.id, timestamp: Date(), online: false)
                st.error = error ?? "SSH 连接失败"
                completion(st)
                return
            }
            completion(Self.parse(output, serverId: server.id))
        }
    }

    // MARK: - SSH 执行

    private func runSSH(server: ServerConfig, command: String, completion: @escaping (String?, String?) -> Void) {
        // askpass 脚本：echo base64(密码) | base64 -D —— 规避密码中的特殊字符
        let askpassPath = "/tmp/ds_askpass_\(server.id.prefix(8)).sh"
        let b64 = Data(server.password.utf8).base64EncodedString()
        let script = "#!/bin/sh\necho \"\(b64)\" | base64 -D\n"
        try? script.write(toFile: askpassPath, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: askpassPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = [
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=8",
            "-o", "LogLevel=ERROR",
            "\(server.username)@\(server.host)",
            command
        ]
        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = askpassPath
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = ":0"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(atPath: askpassPath)
            completion(nil, error.localizedDescription)
            return
        }
        process.waitUntilExit()

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        try? FileManager.default.removeItem(atPath: askpassPath)

        let out = String(data: outData, encoding: .utf8)
        let err = String(data: errData, encoding: .utf8)
        if process.terminationStatus == 0, let out = out, !out.isEmpty {
            completion(out, nil)
        } else {
            completion(out?.isEmpty == false ? out : nil,
                       err?.isEmpty == false ? err : "SSH 退出码 \(process.terminationStatus)")
        }
    }

    // MARK: - 解析

    static func parse(_ raw: String, serverId: String) -> ServerStatus {
        var st = ServerStatus(serverId: serverId, timestamp: Date(), online: true)
        let sections = raw.components(separatedBy: "\n===")
        for section in sections {
            let lines = section.components(separatedBy: "\n")
            guard let head = lines.first else { continue }
            // 第一段以 "===MEM===" 开头，后续段以 "LOAD===" 等开头，统一用 contains 匹配
            if head.contains("MEM") { parseMem(lines, st: &st) }
            else if head.contains("LOAD") { parseLoad(lines, st: &st) }
            else if head.contains("DISK") { parseDisk(lines, st: &st) }
            else if head.contains("PROC") { parseProc(lines, st: &st) }
            else if head.contains("LAST") { parseLast(lines, st: &st) }
        }
        return st
    }

    private static func parseMem(_ lines: [String], st: inout ServerStatus) {
        for line in lines {
            let f = line.split(separator: " ").map(String.init)
            if f.first == "Mem:" && f.count >= 7 {
                st.memTotalMB = Double(f[1]) ?? 0
                st.memUsedMB = Double(f[2]) ?? 0
                st.memAvailMB = Double(f[6]) ?? 0
                if st.memTotalMB > 0 { st.memPercent = (st.memTotalMB - st.memAvailMB) / st.memTotalMB * 100 }
            } else if f.first == "Swap:" && f.count >= 3 {
                let total = Double(f[1]) ?? 0
                let used = Double(f[2]) ?? 0
                if total > 0 { st.swapPercent = used / total * 100 }
            }
        }
    }

    private static func parseLoad(_ lines: [String], st: inout ServerStatus) {
        guard let line = lines.first else { return }
        guard let idx = line.range(of: "load average:") else { return }
        let tail = String(line[idx.upperBound...])
        let nums = tail.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if nums.count >= 3 {
            st.load1 = nums[0]; st.load5 = nums[1]; st.load15 = nums[2]
        }
    }

    private static func parseDisk(_ lines: [String], st: inout ServerStatus) {
        for line in lines where line.hasPrefix("/dev") {
            let f = line.split(separator: " ").map(String.init)
            guard f.count >= 6 else { continue }
            st.diskTotalGB = Self.gbValue(f[1])
            st.diskUsedGB = Self.gbValue(f[2])
            st.diskPercent = Double(f[4].replacingOccurrences(of: "%", with: "")) ?? 0
        }
    }

    private static func parseProc(_ lines: [String], st: inout ServerStatus) {
        var procs: [String] = []
        for line in lines.dropFirst() {   // 跳过表头
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            // 6 段: pid user mem cpu comm args...
            let f = trimmed.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true).map(String.init)
            if f.count >= 6, let mem = Double(f[2]), let cpu = Double(f[3]) {
                let pid = f[0]; let comm = f[4]
                let args = String(f[5].prefix(100))
                let biz = businessName(comm: comm, args: args)
                // 格式: 业务名|comm|mem|cpu|pid（展示端 split 解析）
                procs.append("\(biz)|\(comm)|\(mem)|\(cpu)|\(pid)")
            }
        }
        st.topProcesses = procs
    }

    /// 把进程 comm/args 翻译成可读的业务名（如 deeptutor / ecomm / xray代理）
    static func businessName(comm: String, args: String) -> String {
        let a = args.lowercased()
        if a.contains("deeptutor") { return "deeptutor" }
        if a.contains("ecomm") || a.contains("cyberstroll") || a.contains("ecom-intel") { return "ecomm" }
        if a.contains("openwifi") { return "openwifi" }
        if a.contains("supplier") || a.contains("supply-chain") || a.contains("supply_chain") { return "supply-chain" }
        if a.contains("ai-news") { return "ai-news" }
        if comm.contains("xray-linux") { return "xray代理" }
        if comm.contains("x-ui") { return "xray面板" }
        if comm.contains("next-server") { return "deeptutor-web" }
        if comm.contains("gunicorn") {
            if a.contains("supply-chain-brain") { return "supply-chain-brain" }
            if a.contains("ai-news") { return "ai-news" }
            return "gunicorn"
        }
        if comm.contains("uvicorn") { return a.contains("deeptutor") ? "deeptutor" : "uvicorn" }
        if comm.contains("python") { return a.contains("deeptutor") ? "deeptutor" : "python" }
        if comm == "java" { return "java(ubuntu)" }
        if comm.contains("nginx") { return "nginx" }
        if comm.contains("dockerd") { return "docker" }
        if comm.contains("containerd") { return "containerd" }
        if comm.contains("fail2ban") { return "fail2ban" }
        if comm.contains("fwupd") { return "fwupd" }
        if comm.contains("journal") { return "systemd" }
        if comm.contains("multipathd") { return "multipathd" }
        if comm.contains("cron") { return "cron" }
        if comm.contains("sshd") { return "sshd" }
        if comm.contains("polkit") { return "polkit" }
        return comm   // 兜底用原进程名
    }

    private static func parseLast(_ lines: [String], st: inout ServerStatus) {
        var logins: [LoginRecord] = []
        for line in lines {
            let f = line.split(separator: " ").map(String.init)
            guard f.count >= 7 else { continue }
            // 形如: root pts/0 183.210.193.143 Sun Aug 16 11:54 - 12:00 (00:06)
            let user = f[0]
            let ip = f[2]
            let time = f.count >= 7 ? "\(f[4]) \(f[5]) \(f[6])" : ""   // Aug 16 11:54
            let duration = f.last?.trimmingCharacters(in: CharacterSet(charactersIn: "()")) ?? ""
            logins.append(LoginRecord(user: user, fromIP: ip, time: time, duration: duration))
        }
        st.logins = logins
    }

    private static func gbValue(_ s: String) -> Double {
        if s.hasSuffix("G") { return Double(s.dropLast()) ?? 0 }
        if s.hasSuffix("T") { return (Double(s.dropLast()) ?? 0) * 1024 }
        if s.hasSuffix("M") { return (Double(s.dropLast()) ?? 0) / 1024 }
        return Double(s) ?? 0
    }
}
