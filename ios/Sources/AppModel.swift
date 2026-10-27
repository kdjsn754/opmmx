import Foundation
import SwiftUI
import Citadel
import NIOCore

enum AppError: LocalizedError {
    case notConnected
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "SSH 尚未连接"
        case .message(let value): return value
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var connected = false
    @Published var connecting = false
    @Published var busy = false
    @Published var status = "未连接"
    @Published var errorMessage: String?
    @Published var stats = OverviewStats()
    @Published var routerInfo = RouterInfo()
    @Published var devices: [DeviceInfo] = []
    @Published var ports: [PortInfo] = []
    @Published var openClash = OpenClashInfo()
    @Published var ocMetrics = OpenClashMetrics()
    @Published var accessChecks = AccessCheck.Site.allCases.map { AccessCheck(site: $0) }
    @Published var history: [HistoryPoint] = []
    @Published var profiles: [RouterProfile] = []
    @Published var currentProfileID: UUID?
    @Published var moduleOrder: [OverviewModule] = OverviewModule.allCases
    @Published var hiddenModules: Set<OverviewModule> = []
    @Published var autoLogin: Bool {
        didSet { UserDefaults.standard.set(autoLogin, forKey: "autoLogin") }
    }

    private var client: SSHClient?
    private var pollTask: Task<Void, Never>?
    private var lastCpuTotal: Double?
    private var lastCpuIdle: Double?
    private var lastRx: Double?
    private var lastTx: Double?
    private var lastNetDate: Date?
    private var lastOcPid = ""
    private var lastOcTicks: Double?
    private var lastOcTotal: Double?
    private var pollCount = 0

    init() {
        autoLogin = UserDefaults.standard.object(forKey: "autoLogin") as? Bool ?? true
        loadProfiles()
        loadModules()
    }

    var currentProfile: RouterProfile? {
        profiles.first { $0.id == currentProfileID }
    }

    var visibleModules: [OverviewModule] {
        moduleOrder.filter { !hiddenModules.contains($0) }
    }

    func isVisible(_ module: OverviewModule) -> Bool {
        !hiddenModules.contains(module)
    }

    func setModule(_ module: OverviewModule, visible: Bool) {
        if visible { hiddenModules.remove(module) } else { hiddenModules.insert(module) }
        saveModules()
    }

    func moveModules(from source: IndexSet, to destination: Int) {
        moduleOrder.move(fromOffsets: source, toOffset: destination)
        saveModules()
    }

    func resetModules() {
        moduleOrder = OverviewModule.allCases
        hiddenModules = []
        saveModules()
    }

    // MARK: - Connections

    func connect(host: String, port: Int, user: String, password: String,
                 label: String = "") async {
        let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHost.isEmpty, !password.isEmpty else {
            errorMessage = "请填写路由器地址和密码"
            return
        }

        var profile: RouterProfile
        if let existing = profiles.first(where: {
            $0.host == cleanHost && $0.port == port && $0.user == user
        }) {
            profile = existing
            if !label.isEmpty { profile.label = label }
        } else {
            profile = RouterProfile(label: label, host: cleanHost, port: port, user: user)
            profiles.append(profile)
        }
        currentProfileID = profile.id
        saveProfiles()
        if autoLogin {
            KeychainStore.savePassword(
                password,
                account: KeychainStore.passwordAccount(for: profile)
            )
        }
        await connect(profile: profile, password: password)
    }

    func connect(profile: RouterProfile, password: String) async {
        await disconnect(keepPassword: true)
        connecting = true
        errorMessage = nil
        status = "正在连接…"
        do {
            let username = profile.user
            let settings = SSHClientSettings(
                host: profile.host,
                port: profile.port,
                authenticationMethod: {
                    SSHAuthenticationMethod.passwordBased(
                        username: username,
                        password: password
                    )
                },
                hostKeyValidator: SSHHostKeyValidator.acceptAnything()
            )
            let newClient = try await SSHClient.connect(to: settings)
            client = newClient
            currentProfileID = profile.id
            connected = true
            connecting = false
            status = "已连接"
            await refreshInfo()
            await refreshOpenClash()
            await poll()
            startPolling()
        } catch {
            client = nil
            connected = false
            connecting = false
            status = "连接失败"
            errorMessage = error.localizedDescription
        }
    }

    func autoConnectIfPossible() async {
        guard autoLogin, !connected, let profile = currentProfile,
              let password = KeychainStore.loadPassword(
                account: KeychainStore.passwordAccount(for: profile)
              ) else { return }
        await connect(profile: profile, password: password)
    }

    func switchTo(_ profile: RouterProfile) async {
        guard let password = KeychainStore.loadPassword(
            account: KeychainStore.passwordAccount(for: profile)
        ) else {
            errorMessage = "该连接没有保存密码，请重新输入"
            return
        }
        currentProfileID = profile.id
        saveProfiles()
        await connect(profile: profile, password: password)
    }

    func saveNewProfile(host: String, port: Int, user: String,
                        password: String, label: String) async {
        await connect(host: host, port: port, user: user, password: password, label: label)
    }

    func deleteProfile(_ profile: RouterProfile) {
        KeychainStore.deletePassword(account: KeychainStore.passwordAccount(for: profile))
        profiles.removeAll { $0.id == profile.id }
        if currentProfileID == profile.id {
            currentProfileID = profiles.first?.id
        }
        saveProfiles()
    }

    func disconnect(keepPassword: Bool = false) async {
        pollTask?.cancel()
        pollTask = nil
        if let client { try? await client.close() }
        client = nil
        connected = false
        busy = false
        connecting = false
        status = "未连接"
        lastCpuTotal = nil
        lastCpuIdle = nil
        lastRx = nil
        lastTx = nil
        lastNetDate = nil
        lastOcPid = ""
        lastOcTicks = nil
        lastOcTotal = nil
        if !keepPassword, let profile = currentProfile {
            KeychainStore.deletePassword(account: KeychainStore.passwordAccount(for: profile))
        }
    }

    func logout() async {
        await disconnect(keepPassword: false)
        for profile in profiles {
            KeychainStore.deletePassword(account: KeychainStore.passwordAccount(for: profile))
        }
        profiles = []
        currentProfileID = nil
        saveProfiles()
        stats = OverviewStats()
        routerInfo = RouterInfo()
        devices = []
        ports = []
        history = []
    }

    // MARK: - SSH

    func execute(_ command: String) async throws -> String {
        guard let client else { throw AppError.notConnected }
        let buffer = try await client.executeCommand(command)
        return String(decoding: Data(buffer.readableBytesView), as: UTF8.self)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func poll() async {
        guard connected else { return }
        do {
            let sections = parseSections(try await execute(pollCommand))
            updateCPU(sections["STAT"] ?? "")
            updateMemory(sections["MEM"] ?? "")
            stats.wanDevice = parseWan(sections["ROUTE"] ?? "")
            updateNetwork(sections["NET"] ?? "")
            if let value = firstLine(sections["UPTIME"]).split(separator: " ").first,
               let uptime = Double(value) {
                stats.uptime = uptime
            }
            if let value = firstLine(sections["LOAD"]).split(separator: " ").first,
               let load = Double(value) {
                stats.load = load
            }
            updateSensors(temp: sections["TEMP"] ?? "", fan: sections["FAN"] ?? "")
            updateDevices(sections["LEASES"] ?? "")
            updatePorts(ports: sections["PORTS"] ?? "", brif: sections["BRIF"] ?? "")
            if openClash.running {
                await refreshOpenClashMetrics()
            }
            pollCount += 1
            if pollCount % 5 == 0 {
                await refreshOpenClash()
            }
            appendHistory()
            status = "已连接"
        } catch {
            status = "连接中断"
        }
    }

    func refreshInfo() async {
        do {
            let sections = parseSections(try await execute(infoCommand))
            var value = RouterInfo()
            value.model = firstLine(sections["MODEL"])
            value.hostname = firstLine(sections["HOST"])
            value.kernel = firstLine(sections["KERNEL"])
            value.architecture = firstLine(sections["ARCH"])
            value.cpuModel = parseCPUModel(sections["CPUINFO"] ?? "")
            let release = sections["RELEASE"] ?? ""
            value.firmware = parseRelease(release)
            if let load = firstLine(sections["LOAD"]).split(separator: " ").first {
                value.load = String(load)
            }
            routerInfo = value
            openClash = parseOpenClashInfo(sections, current: openClash)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshOpenClash() async {
        do {
            let sections = parseSections(try await execute(openClashCommand))
            openClash = parseOpenClashInfo(sections, current: openClash)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshOpenClashMetrics() async {
        do {
            let raw = try await execute(ocMetricsCommand)
            let sections = parseSections(raw)
            var value = OpenClashMetrics()
            if let data = json(sections["TRAFFIC"]),
               let up = data["up"] as? Double, let down = data["down"] as? Double {
                value.upload = up
                value.download = down
            }
            if let data = json(sections["CONN"]) {
                value.uploadTotal = UInt64((data["uploadTotal"] as? Int) ?? 0)
                value.downloadTotal = UInt64((data["downloadTotal"] as? Int) ?? 0)
                value.connections = (data["connections"] as? [[String: Any]])?.count ?? 0
            }
            value.memory = parseVmRSS(sections["OCSTATUS"] ?? "")
            value.load = parseCoreLoad(sections)
            updateCoreCPU(sections, into: &value)
            ocMetrics = value
        } catch {
            // Metrics are optional; don't replace the page status with a metrics error.
        }
    }

    func startOpenClash() async {
        if openClash.running {
            errorMessage = nil
            status = "OpenClash 已启动"
            return
        }
        await action("uci -q set openclash.config.enable='1'; uci -q commit openclash; /etc/init.d/openclash start >/dev/null 2>&1; echo done")
    }

    func stopOpenClash() async {
        if !openClash.running {
            errorMessage = nil
            status = "OpenClash 已关闭"
            return
        }
        await action("uci -q set openclash.config.enable='0'; uci -q commit openclash; /etc/init.d/openclash stop >/dev/null 2>&1; echo done")
    }

    func restartOpenClash() async {
        await action("uci -q set openclash.config.enable='1'; uci -q commit openclash; /etc/init.d/openclash restart >/dev/null 2>&1; echo done")
    }

    func switchMode(_ mode: String) async {
        await action("uci -q set openclash.config.proxy_mode='\(mode)'; uci -q set 'openclash.@overwrite[0].proxy_mode'='\(mode)'; uci -q commit openclash; /etc/init.d/openclash restart >/dev/null 2>&1; echo done")
    }

    func switchConfig(_ name: String) async {
        guard !name.isEmpty, !name.contains("'") else { return }
        await action("uci -q set openclash.config.config_path='/etc/openclash/config/\(name)'; uci -q set openclash.config.enable='1'; uci -q commit openclash; /etc/init.d/openclash restart >/dev/null 2>&1; echo done")
    }

    private func action(_ command: String) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await execute(command)
            try? await Task.sleep(for: .seconds(2))
            await refreshOpenClash()
            status = "已连接"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkAccess() async {
        guard connected else { return }
        busy = true
        defer { busy = false }
        do {
            let sections = parseSections(try await execute(accessCommand))
            var results: [AccessCheck.Site: (Bool, Int)] = [:]
            for line in (sections["CHECK"] ?? "").split(separator: "\n") {
                let fields = line.split(separator: "\t").map(String.init)
                guard fields.count >= 4, fields[0] == "C",
                      let site = AccessCheck.Site(rawValue: fields[1]) else { continue }
                results[site] = (fields[2] == "1", Int(fields[3]) ?? 0)
            }
            accessChecks = AccessCheck.Site.allCases.map { site in
                let previous = accessChecks.first { $0.site == site }
                var check = AccessCheck(site: site, tested: true)
                if let result = results[site] {
                    check.success = result.0
                    check.latency = result.1
                    check.history = Array(((previous?.history ?? []) + [result.1]).suffix(10))
                }
                return check
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parsing

    private func parseOpenClashInfo(_ sections: [String: String],
                                    current: OpenClashInfo) -> OpenClashInfo {
        var info = current
        let state = firstLine(sections["OCSTATE"])
        info.installed = ["running", "stopped", "installed"].contains(state)
        info.running = state == "running"
        if !info.running {
            ocMetrics = OpenClashMetrics()
        }
        info.mode = firstLine(sections["OCMODE"])
        if info.mode.isEmpty { info.mode = "rule" }
        info.config = (firstLine(sections["OCCONFIG"]) as NSString).lastPathComponent
        info.configs = (sections["OCCONFIGS"] ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        let port = Int(firstLine(sections["OCPORT"])) ?? 9090
        info.panelPort = port
        info.secret = firstLine(sections["OCSECRET"])
        info.dashboards = (sections["OCDIRS"] ?? "")
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        var dash = firstLine(sections["OCDASH"]).lowercased()
        if dash.isEmpty || (!info.dashboards.isEmpty && !info.dashboards.contains(dash)) {
            dash = info.dashboards.first ?? "zashboard"
        }
        info.dashboard = dash
        info.panelURL = buildPanelURL(info)
        return info
    }

    private func buildPanelURL(_ info: OpenClashInfo) -> URL? {
        guard let profile = currentProfile else { return nil }
        let base = "http://\(profile.host):\(info.panelPort)/ui/\(info.dashboard)"
        let host = profile.host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profile.host
        let secret = info.secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let secretPart = secret.isEmpty ? "" : "&secret=\(secret)"
        switch info.dashboard {
        case "yacd":
            return URL(string: "\(base)/?hostname=\(host)&port=\(info.panelPort)\(secretPart)")
        case "dashboard":
            return URL(string: "\(base)/#/?host=\(host)&port=\(info.panelPort)\(secretPart)")
        case "zashboard", "metacubexd":
            return URL(string: "\(base)/#/setup?hostname=\(host)&port=\(info.panelPort)\(secretPart)")
        default:
            return URL(string: base + "/")
        }
    }

    private func updateCPU(_ text: String) {
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("cpu ") }) else { return }
        let values = line.split(separator: " ").dropFirst().compactMap { Double($0) }
        guard values.count >= 4 else { return }
        let total = values.prefix(8).reduce(0, +)
        let idle = values[3] + (values.count > 4 ? values[4] : 0)
        if let lastTotal = lastCpuTotal, let lastIdle = lastCpuIdle {
            let deltaTotal = total - lastTotal
            let deltaIdle = idle - lastIdle
            if deltaTotal > 0 {
                stats.cpu = max(0, min(100, (deltaTotal - deltaIdle) / deltaTotal * 100))
            }
        }
        lastCpuTotal = total
        lastCpuIdle = idle
    }

    private func updateMemory(_ text: String) {
        var total: UInt64 = 0
        var available: UInt64 = 0
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else { continue }
            if parts[0] == "MemTotal:" { total = (UInt64(parts[1]) ?? 0) * 1024 }
            if parts[0] == "MemAvailable:" { available = (UInt64(parts[1]) ?? 0) * 1024 }
        }
        stats.memoryTotal = total
        stats.memoryUsed = total > available ? total - available : 0
    }

    private func updateNetwork(_ text: String) {
        guard !stats.wanDevice.isEmpty else { return }
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(stats.wanDevice + ":") else { continue }
            let numbers = trimmed.split(separator: ":").dropFirst().joined()
                .split(separator: " ").compactMap { Double($0) }
            guard numbers.count >= 9 else { return }
            let rx = numbers[0]
            let tx = numbers[8]
            let now = Date()
            if let lastRx, let lastTx, let lastNetDate {
                let elapsed = now.timeIntervalSince(lastNetDate)
                if elapsed > 0 {
                    stats.download = max(0, (rx - lastRx) / elapsed)
                    stats.upload = max(0, (tx - lastTx) / elapsed)
                    stats.sessionDownload += max(0, rx - lastRx)
                    stats.sessionUpload += max(0, tx - lastTx)
                }
            }
            lastRx = rx
            lastTx = tx
            lastNetDate = now
            return
        }
    }

    private func updateSensors(temp: String, fan: String) {
        let temps = temp.split(separator: "\n").compactMap { line -> Double? in
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[0] == "T" else { return nil }
            let value = Double(parts[1]) ?? 0
            return value > 1000 ? value / 1000 : value
        }
        if let value = temps.max(), value > 0 { stats.temperature = value }
        let fans = fan.split(separator: "\n").compactMap { line -> Double? in
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[0] == "F" else { return nil }
            return Double(parts[1])
        }
        if let value = fans.max(), value > 0 { stats.fanRPM = value }
    }

    private func updateDevices(_ text: String) {
        var result: [DeviceInfo] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ").map(String.init)
            guard fields.count >= 4 else { continue }
            result.append(DeviceInfo(
                ip: fields[2],
                mac: fields[1],
                name: fields[3] == "*" ? fields[2] : fields[3]
            ))
        }
        devices = result
    }

    private func updatePorts(ports portText: String, brif: String) {
        let bridge = Set(brif.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
        var result: [PortInfo] = []
        for line in portText.split(separator: "\n") {
            let fields = line.split(separator: "\t").map(String.init)
            guard fields.count >= 9, fields[0] == "P" else { continue }
            let name = fields[1]
            let isLan = name == "br-lan" || name.hasPrefix("lan") || bridge.contains(name)
            guard isLan else { continue }
            result.append(PortInfo(
                name: name,
                state: fields[2],
                speed: fields[3],
                duplex: fields[4],
                rx: UInt64(fields[5]) ?? 0,
                tx: UInt64(fields[6]) ?? 0,
                ip: fields[7],
                bridgePorts: bridge.count
            ))
        }
        self.ports = result
    }

    private func updateCoreCPU(_ sections: [String: String], into value: inout OpenClashMetrics) {
        let pid = firstLine(sections["OCPID"])
        let stat = sections["OCSTAT"] ?? ""
        let sys = sections["SYSTAT"] ?? ""
        guard let procTicks = parseProcTicks(stat), let total = parseTotalTicks(sys) else { return }
        if pid != lastOcPid {
            lastOcPid = pid
            lastOcTicks = nil
            lastOcTotal = nil
        }
        if let lastTicks = lastOcTicks, let lastTotal = lastOcTotal,
           total > lastTotal, procTicks >= lastTicks {
            value.cpu = max(0, (procTicks - lastTicks) / (total - lastTotal) * 100)
        }
        lastOcTicks = procTicks
        lastOcTotal = total
    }

    private func parseCoreLoad(_ sections: [String: String]) -> Double {
        let cores = max(1, Double(Int(firstLine(sections["CPUS"])) ?? 1))
        let fields = firstLine(sections["LOAD"]).split(separator: " ")
        guard fields.count >= 2, let load = Double(fields[1]) else { return 0 }
        return max(0, load / cores * 100)
    }

    private func parseVmRSS(_ status: String) -> UInt64 {
        for line in status.split(separator: "\n") where line.hasPrefix("VmRSS:") {
            let parts = line.split(separator: " ")
            if parts.count >= 2 { return (UInt64(parts[1]) ?? 0) * 1024 }
        }
        return 0
    }

    private func parseProcTicks(_ stat: String) -> Double? {
        guard let close = stat.lastIndex(of: ")") else { return nil }
        let rest = stat[stat.index(after: close)...].split(separator: " ")
        guard rest.count >= 13 else { return nil }
        return (Double(rest[11]) ?? 0) + (Double(rest[12]) ?? 0)
    }

    private func parseTotalTicks(_ stat: String) -> Double? {
        guard let line = stat.split(separator: "\n").first else { return nil }
        let fields = line.split(separator: " ")
        guard fields.count >= 5 else { return nil }
        return fields.dropFirst().prefix(8).compactMap { Double($0) }.reduce(0, +)
    }

    private func parseWan(_ route: String) -> String {
        guard let range = route.range(of: "dev ") else { return "" }
        return route[range.upperBound...].split(separator: " ").first.map(String.init) ?? ""
    }

    private func parseCPUModel(_ text: String) -> String {
        var fallback = ""
        for line in text.split(separator: "\n") {
            let lower = line.lowercased()
            let value = (line.split(separator: ":", maxSplits: 1).last.map(String.init) ?? "")
                .trimmingCharacters(in: .whitespaces)
            if lower.contains("model name") || lower.contains("cpu model") {
                if !value.isEmpty { return value }
            }
            if lower.hasPrefix("processor") && fallback.isEmpty {
                fallback = value
            }
        }
        return fallback
    }

    private func parseRelease(_ text: String) -> String {
        for line in text.split(separator: "\n") {
            if line.contains("DISTRIB_DESCRIPTION") || line.contains("PRETTY_NAME") {
                let value = (line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                if !value.isEmpty { return value }
            }
        }
        return ""
    }

    private func appendHistory() {
        history.append(HistoryPoint(
            date: Date(),
            cpu: stats.cpu,
            memory: memoryFraction * 100,
            download: stats.download,
            upload: stats.upload
        ))
        if history.count > 60 { history.removeFirst(history.count - 60) }
    }

    var memoryFraction: Double {
        stats.memoryTotal > 0 ? Double(stats.memoryUsed) / Double(stats.memoryTotal) : 0
    }

    private func splitSections(_ raw: String) -> [String: String] {
        parseSections(raw)
    }

    private func parseSections(_ raw: String) -> [String: String] {
        var result: [String: String] = [:]
        var key: String?
        for line in raw.replacingOccurrences(of: "\r", with: "").split(
            separator: "\n", omittingEmptySubsequences: false
        ) {
            if line.hasPrefix("@@") {
                key = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                result[key!] = ""
            } else if let key {
                result[key, default: ""] += String(line) + "\n"
            }
        }
        return result
    }

    private func firstLine(_ text: String?) -> String {
        guard let text else { return "" }
        return text.split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
    }

    private func json(_ text: String?) -> [String: Any]? {
        guard let text, let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let value = String(text[start...end])
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object as? [String: Any]
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: "profiles"),
              let decoded = try? JSONDecoder().decode([RouterProfile].self, from: data) else {
            return
        }
        profiles = decoded
        if let raw = UserDefaults.standard.string(forKey: "currentProfileID"),
           let id = UUID(uuidString: raw) {
            currentProfileID = id
        }
        if currentProfileID == nil { currentProfileID = profiles.first?.id }
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "profiles")
        }
        UserDefaults.standard.set(currentProfileID?.uuidString, forKey: "currentProfileID")
    }

    private func loadModules() {
        if let raw = UserDefaults.standard.stringArray(forKey: "moduleOrder") {
            let values = raw.compactMap(OverviewModule.init(rawValue:))
            if !values.isEmpty { moduleOrder = values }
        }
        let hidden = UserDefaults.standard.stringArray(forKey: "hiddenModules") ?? []
        hiddenModules = Set(hidden.compactMap(OverviewModule.init(rawValue:)))
        let missing = OverviewModule.allCases.filter { !moduleOrder.contains($0) }
        moduleOrder.append(contentsOf: missing)
    }

    private func saveModules() {
        UserDefaults.standard.set(moduleOrder.map(\.rawValue), forKey: "moduleOrder")
        UserDefaults.standard.set(hiddenModules.map(\.rawValue), forKey: "hiddenModules")
    }
}

// MARK: - Commands

private extension AppModel {
    var infoCommand: String {
        """
        echo @@MODEL; cat /tmp/sysinfo/model 2>/dev/null
        echo @@HOST; cat /proc/sys/kernel/hostname 2>/dev/null
        echo @@RELEASE; cat /etc/openwrt_release 2>/dev/null
        echo @@KERNEL; uname -r 2>/dev/null
        echo @@ARCH; uname -m 2>/dev/null
        echo @@CPUINFO; sed -n '1,80p' /proc/cpuinfo 2>/dev/null
        echo @@UPTIME; cat /proc/uptime 2>/dev/null
        echo @@LOAD; cat /proc/loadavg 2>/dev/null
        echo @@OCSTATE
        if [ -x /etc/init.d/openclash ]; then
          if /etc/init.d/openclash status >/dev/null 2>&1 || pidof clash >/dev/null 2>&1; then echo running; else echo stopped; fi
        elif [ -d /usr/share/openclash ]; then echo installed; else echo missing; fi
        echo @@OCMODE; uci -q get openclash.config.proxy_mode 2>/dev/null
        echo @@OCCONFIG; uci -q get openclash.config.config_path 2>/dev/null
        echo @@OCCONFIGS; ls /etc/openclash/config/*.yaml /etc/openclash/config/*.yml 2>/dev/null | xargs -n1 basename 2>/dev/null
        echo @@OCPORT; p=$(uci -q get openclash.config.cn_port 2>/dev/null); [ -z "$p" ] && p=9090; echo "$p"
        echo @@OCSECRET; uci -q get openclash.config.dashboard_password 2>/dev/null
        echo @@OCDASH; uci -q get openclash.config.default_dashboard 2>/dev/null
        echo @@OCDIRS; for d in zashboard metacubexd yacd dashboard; do [ -d "/usr/share/openclash/ui/$d" ] && echo "$d"; done
        """
    }

    var pollCommand: String {
        """
        echo @@STAT; cat /proc/stat 2>/dev/null
        echo @@MEM; cat /proc/meminfo 2>/dev/null
        echo @@NET; cat /proc/net/dev 2>/dev/null
        echo @@ROUTE; ip route show default 2>/dev/null
        echo @@UPTIME; cat /proc/uptime 2>/dev/null
        echo @@LOAD; cat /proc/loadavg 2>/dev/null
        echo @@TEMP
        for f in /sys/class/thermal/thermal_zone*/temp; do [ -f "$f" ] && echo "T $(cat "$f" 2>/dev/null)"; done
        for f in /sys/class/hwmon/hwmon*/temp*_input; do [ -f "$f" ] && echo "T $(cat "$f" 2>/dev/null)"; done
        echo @@FAN
        for f in /sys/class/hwmon/hwmon*/fan*_input; do [ -f "$f" ] && echo "F $(cat "$f" 2>/dev/null)"; done
        echo @@LEASES; cat /tmp/dhcp.leases 2>/dev/null
        echo @@BRIF; ls /sys/class/net/br-lan/brif 2>/dev/null
        echo @@PORTS
        for d in /sys/class/net/*; do
          n=${d##*/}; [ "$n" = "lo" ] && continue
          s=$(cat "$d/operstate" 2>/dev/null); sp=$(cat "$d/speed" 2>/dev/null)
          dx=$(cat "$d/duplex" 2>/dev/null); a=$(ip -4 -o addr show dev "$n" 2>/dev/null | awk '{print $4}' | head -n1)
          r=$(awk -v n="$n" '$0 ~ n":" {gsub(/^[ \\t]+/,""); split($0,x,":"); split(x[2],y," "); print y[1], y[9]}' /proc/net/dev)
          set -- $r; rx=${1:-0}; tx=${2:-0}; br=$(ls /sys/class/net/br-lan/brif 2>/dev/null | wc -l)
          printf 'P\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "$n" "$s" "$sp" "$dx" "$rx" "$tx" "$a" "$br"
        done
        """
    }

    var openClashCommand: String {
        """
        echo @@OCSTATE
        if [ -x /etc/init.d/openclash ]; then
          if /etc/init.d/openclash status >/dev/null 2>&1 || pidof clash >/dev/null 2>&1; then echo running; else echo stopped; fi
        elif [ -d /usr/share/openclash ]; then echo installed; else echo missing; fi
        echo @@OCMODE; uci -q get openclash.config.proxy_mode 2>/dev/null
        echo @@OCCONFIG; uci -q get openclash.config.config_path 2>/dev/null
        echo @@OCCONFIGS; ls /etc/openclash/config/*.yaml /etc/openclash/config/*.yml 2>/dev/null | xargs -n1 basename 2>/dev/null
        echo @@OCPORT; p=$(uci -q get openclash.config.cn_port 2>/dev/null); [ -z "$p" ] && p=9090; echo "$p"
        echo @@OCSECRET; uci -q get openclash.config.dashboard_password 2>/dev/null
        echo @@OCDASH; uci -q get openclash.config.default_dashboard 2>/dev/null
        echo @@OCDIRS; for d in zashboard metacubexd yacd dashboard; do [ -d "/usr/share/openclash/ui/$d" ] && echo "$d"; done
        """
    }

    var ocMetricsCommand: String {
        """
        echo @@TRAFFIC
        port=$(uci -q get openclash.config.cn_port 2>/dev/null); [ -z "$port" ] && port=9090
        secret=$(uci -q get openclash.config.dashboard_password 2>/dev/null)
        if [ -n "$secret" ]; then curl -s --max-time 4 -H "Authorization: Bearer $secret" "http://127.0.0.1:$port/traffic" 2>/dev/null; else curl -s --max-time 4 "http://127.0.0.1:$port/traffic" 2>/dev/null; fi
        echo
        echo @@CONN
        if [ -n "$secret" ]; then curl -s --max-time 4 -H "Authorization: Bearer $secret" "http://127.0.0.1:$port/connections" 2>/dev/null; else curl -s --max-time 4 "http://127.0.0.1:$port/connections" 2>/dev/null; fi
        echo
        echo @@OCPID; pid=$(pidof clash 2>/dev/null); [ -z "$pid" ] && pid=$(pidof mihomo 2>/dev/null); echo "$pid"
        echo @@OCSTATUS; [ -n "$pid" ] && cat /proc/$pid/status 2>/dev/null
        echo @@OCSTAT; [ -n "$pid" ] && cat /proc/$pid/stat 2>/dev/null
        echo @@SYSTAT; head -n1 /proc/stat 2>/dev/null
        echo @@LOAD; cat /proc/loadavg 2>/dev/null
        echo @@CPUS; grep -c ^processor /proc/cpuinfo 2>/dev/null
        """
    }

    var accessCommand: String {
        """
        echo @@CHECK
        check(){ key=$1; domain=$2; r=$(curl -sIL -m 8 -o /dev/null -w '%{http_code} %{time_total}' "https://$domain" 2>/dev/null); code=${r%% *}; sec=${r##* }
        if [ -n "$code" ] && [ "$code" != "000" ] && [ -n "$sec" ]; then
          ms=$(awk "BEGIN{printf \\"%d\\", $sec*1000}")
          printf 'C\\t%s\\t1\\t%s\\n' "$key" "$ms"
        else
          printf 'C\\t%s\\t0\\t0\\n' "$key"
        fi; }
        check baidu www.baidu.com; check netease music.163.com; check github github.com; check youtube www.youtube.com
        """
    }
}

func formatBytes(_ value: Double) -> String {
    let units = ["B", "KB", "MB", "GB", "TB"]
    var number = max(0, value)
    var index = 0
    while number >= 1024 && index < units.count - 1 {
        number /= 1024
        index += 1
    }
    return String(format: index == 0 ? "%.0f %@" : "%.1f %@", number, units[index])
}

func formatSpeed(_ value: Double) -> String {
    formatBytes(value) + "/s"
}

func formatUptime(_ seconds: Double) -> String {
    let total = Int(seconds)
    let days = total / 86400
    let hours = (total % 86400) / 3600
    let minutes = (total % 3600) / 60
    if days > 0 { return "\(days)天 \(hours)小时" }
    if hours > 0 { return "\(hours)小时 \(minutes)分钟" }
    return "\(minutes)分钟"
}
