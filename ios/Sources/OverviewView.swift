import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selectedTab: Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    ForEach(model.visibleModules) { module in
                        moduleView(module)
                    }
                }
                .padding(16)
            }
            .background(Color.clear)
            .navigationTitle("概览")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            await model.refreshInfo()
                            await model.refreshOpenClash()
                            await model.poll()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .refreshable {
                await model.refreshInfo()
                await model.refreshOpenClash()
                await model.poll()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.router.fill")
                .font(.system(size: 28))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.routerInfo.model.isEmpty ? "OpenWrt" : model.routerInfo.model)
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(model.connected ? .green : .orange)
                        .frame(width: 7, height: 7)
                    Text(model.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.stats.wanDevice.isEmpty {
                        Text("· \(model.stats.wanDevice)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func moduleView(_ module: OverviewModule) -> some View {
        switch module {
        case .speed:
            moduleCard(module) { speedContent }
        case .resources:
            moduleCard(module) { resourcesContent }
        case .hardware:
            moduleCard(module) { hardwareContent }
        case .devices:
            moduleCard(module) { devicesContent }
        case .ports:
            moduleCard(module) { portsContent }
        case .openclash:
            Button {
                selectedTab = 1
            } label: {
                moduleCard(module) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.openClash.installed
                                 ? (model.openClash.running ? "运行中" : "已停止")
                                 : "未安装")
                                .font(.subheadline.weight(.semibold))
                            Text("查看状态、模式与配置文件")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(model.openClash.mode.uppercased())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        case .trend:
            moduleCard(module) { trendContent }
        case .system:
            moduleCard(module) { systemContent }
        }
    }

    private func moduleCard<Content: View>(
        _ module: OverviewModule,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(module.title, systemImage: module.icon)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var speedContent: some View {
        VStack(spacing: 10) {
            HStack {
                speedValue("下载", value: formatSpeed(model.stats.download), color: .blue, icon: "arrow.down")
                Divider().frame(height: 34)
                speedValue("上传", value: formatSpeed(model.stats.upload), color: .purple, icon: "arrow.up")
            }
            if model.history.count > 1 {
                Chart(model.history) { point in
                    LineMark(x: .value("时间", point.date), y: .value("下载", point.download))
                        .foregroundStyle(.blue)
                    LineMark(x: .value("时间", point.date), y: .value("上传", point.upload))
                        .foregroundStyle(.purple)
                }
                .chartXAxis(.hidden)
                .frame(height: 76)
            }
            HStack {
                Text("本次会话 ↓ \(formatBytes(model.stats.sessionDownload))")
                Spacer()
                Text("↑ \(formatBytes(model.stats.sessionUpload))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func speedValue(_ label: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resourcesContent: some View {
        HStack(spacing: 12) {
            resourceTile(
                title: "CPU",
                value: String(format: "%.0f%%", model.stats.cpu),
                detail: "\(model.routerInfo.cpuModel)",
                fraction: model.stats.cpu / 100,
                color: .orange
            )
            resourceTile(
                title: "内存",
                value: formatBytes(Double(model.stats.memoryUsed)),
                detail: "共 \(formatBytes(Double(model.stats.memoryTotal)))",
                fraction: model.memoryFraction,
                color: .blue
            )
        }
    }

    private func resourceTile(
        title: String,
        value: String,
        detail: String,
        fraction: Double,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            ProgressView(value: max(0, min(1, fraction)))
                .tint(color)
            Text(detail.isEmpty ? "--" : detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var hardwareContent: some View {
        HStack(spacing: 12) {
            hardwareTile(
                icon: "thermometer.medium",
                title: "温度",
                value: model.stats.temperature.map { String(format: "%.1f °C", $0) } ?? "无传感器",
                color: .orange
            )
            hardwareTile(
                icon: "fanblades",
                title: "风扇",
                value: model.stats.fanRPM.map { String(format: "%.0f RPM", $0) } ?? "无传感器",
                color: .teal
            )
        }
    }

    private func hardwareTile(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold))
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
    }

    private var devicesContent: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(model.devices.count)")
                    .font(.title.bold())
                    .foregroundStyle(.green)
                Text("台设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("仅 DHCP 租约")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(model.devices.prefix(4)) { device in
                HStack {
                    Text(device.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(device.ip)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if !model.devices.isEmpty {
                NavigationLink("查看全部设备") {
                    DeviceListView()
                }
                .font(.caption)
            }
        }
    }

    private var portsContent: some View {
        VStack(spacing: 8) {
            if model.ports.isEmpty {
                Text("未发现 LAN 端口").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.ports) { port in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Circle()
                                .fill(port.state == "up" ? .green : .gray)
                                .frame(width: 6, height: 6)
                            Text(port.name)
                                .font(.caption.weight(.medium))
                            Text(port.speed.isEmpty ? "--" : "\(port.speed) Mb/s")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(port.ip.isEmpty ? "--" : port.ip)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("↓ \(formatBytes(Double(port.rx)))")
                            Text("↑ \(formatBytes(Double(port.tx)))")
                            if !port.duplex.isEmpty {
                                Text(port.duplex)
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var trendContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.history.count > 1 {
                Chart(model.history) { point in
                    LineMark(x: .value("时间", point.date), y: .value("CPU", point.cpu))
                        .foregroundStyle(.orange)
                    LineMark(x: .value("时间", point.date), y: .value("内存", point.memory))
                        .foregroundStyle(.blue)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .frame(height: 90)
            } else {
                Text("正在采集…").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Label("CPU", systemImage: "circle.fill").foregroundStyle(.orange)
                Label("内存", systemImage: "circle.fill").foregroundStyle(.blue)
            }
            .font(.caption2)
        }
    }

    private var systemContent: some View {
        VStack(spacing: 0) {
            InfoRow(label: "主机名", value: model.routerInfo.hostname.isEmpty ? "--" : model.routerInfo.hostname)
            Divider()
            InfoRow(label: "型号", value: model.routerInfo.model.isEmpty ? "--" : model.routerInfo.model)
            Divider()
            InfoRow(label: "架构", value: model.routerInfo.architecture.isEmpty ? "--" : model.routerInfo.architecture)
            Divider()
            InfoRow(label: "固件", value: model.routerInfo.firmware.isEmpty ? "--" : model.routerInfo.firmware)
            Divider()
            InfoRow(label: "内核", value: model.routerInfo.kernel.isEmpty ? "--" : model.routerInfo.kernel)
            Divider()
            InfoRow(label: "运行时间", value: formatUptime(model.stats.uptime))
            Divider()
            InfoRow(label: "负载", value: String(format: "%.2f", model.stats.load))
            Divider()
            InfoRow(label: "OpenClash", value: model.openClash.running ? "运行中" : "已停止",
                    color: model.openClash.running ? .green : .secondary)
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 9)
    }
}

extension View {
    func cardStyle() -> some View {
        glassCard(padding: 14, cornerRadius: 22)
    }
    }
}
