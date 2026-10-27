import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("themeMode") private var themeMode = "system"
    @State private var confirmLogout = false
    @State private var showNewConnection = false

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: $themeMode) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    NavigationLink {
                        ModuleSettingsView()
                    } label: {
                        Label("管理概览模块", systemImage: "square.grid.2x2")
                    }
                }

                Section("路由器") {
                    if let profile = model.currentProfile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.title).font(.subheadline.weight(.semibold))
                            Text(profile.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    ForEach(model.profiles) { profile in
                        Button {
                            Task { await model.switchTo(profile) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.title)
                                    Text(profile.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if profile.id == model.currentProfileID {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                model.deleteProfile(profile)
                            }
                        }
                    }

                    Button {
                        showNewConnection = true
                    } label: {
                        Label("新建连接", systemImage: "plus.circle")
                    }

                    Toggle("自动登录", isOn: Binding(
                        get: { model.autoLogin },
                        set: { model.autoLogin = $0 }
                    ))

                    if let error = model.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }

                Section {
                    Text("所有监控数据只在本机和路由器之间传输，不经过云端。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("断开并清除密码", role: .destructive) {
                        confirmLogout = true
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: "1.2.0")
                    LabeledContent("连接方式", value: "SSH 直连")
                    LabeledContent("OpenClash", value: model.openClash.installed ? "已安装" : "未检测到")
                }
            }
            .navigationTitle("设置")
            .sheet(isPresented: $showNewConnection) {
                NewConnectionView()
            }
            .confirmationDialog("退出后需要重新输入密码", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("断开并清除密码", role: .destructive) {
                    Task { await model.logout() }
                }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

private struct NewConnectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var host = ""
    @State private var port = "22"
    @State private var user = "root"
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("连接信息") {
                    TextField("名称（可选）", text: $label)
                    TextField("路由器地址", text: $host)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    TextField("SSH 端口", text: $port)
                        .keyboardType(.numberPad)
                    TextField("用户名", text: $user)
                        .textInputAutocapitalization(.never)
                    SecureField("密码", text: $password)
                }

                Section {
                    Button {
                        Task {
                            await model.saveNewProfile(
                                host: host,
                                port: Int(port) ?? 22,
                                user: user,
                                password: password,
                                label: label
                            )
                            if model.connected { dismiss() }
                        }
                    } label: {
                        HStack {
                            if model.connecting { ProgressView() }
                            Text(model.connecting ? "正在连接…" : "连接并保存")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(model.connecting || host.isEmpty || password.isEmpty)
                }

                if let error = model.errorMessage {
                    Section {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("新建连接")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
