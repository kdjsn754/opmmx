# OpenWrt Monitor — iOS

Android 版的 iOS 原生 SwiftUI 移植，包含：

- SSH 直连 OpenWrt，密码登录
- Keychain 自动登录
- 多路由器连接配置：切换、新建、删除
- 概览：
  - CPU、内存、实时上下行、会话流量
  - 温度和风扇转速
  - DHCP 租约设备及详情
  - 仅 LAN 端口 / LAN 桥接
  - 系统信息（主机名、型号、架构、固件、内核、运行时间、负载）
  - 速度曲线和 CPU/内存趋势
- 概览模块：
  - 显示/隐藏
  - 拖动排序
  - 恢复默认
- 网络代理：
  - OpenClash 状态
  - 规则 / 全局 / 直连
  - 启动 / 关闭 / 重启（已运行时只提示，不重复发命令）
  - 运行数据：上传、下行、总量、连接数、内存、CPU、负载
  - 配置文件选择 + 独立“切换配置”按钮
  - 控制面板：App 内 WKWebView 打开
  - 访问检查：百度、网易云音乐、GitHub、YouTube，带延迟、状态、趋势
- 设置：
  - 跟随系统 / 浅色 / 深色
  - 概览模块管理
  - 路由器切换
  - 自动登录
  - 断开并清除密码
- 不显示订阅用量和 IP 地址卡片

## 构建

IPA 需要 macOS + Xcode + Apple 签名。当前仓库提供 GitHub Actions 的未签名 IPA 流程。

### GitHub Actions

1. 把整个仓库（包含 `ios/` 和 `.github/workflows/ios-unsigned.yml`）推到 GitHub。
2. Actions → **Build unsigned iOS IPA** → Run workflow。
3. 下载 artifact `OpenWrtMonitor-unsigned-ipa`。
4. 用 Sideloadly / AltStore 配合自己的 Apple ID 签名安装。

### Mac 本地

```bash
brew install xcodegen
cd ios
xcodegen generate
open OpenWrtMonitor.xcodeproj
```

或在 `ios/` 下运行：

```bash
chmod +x build-unsigned-ipa.sh
./build-unsigned-ipa.sh
```

生成 `build/OpenWrtMonitor-unsigned.ipa`。

## 依赖

- iOS 17+
- Xcode 15+
- [Citadel](https://github.com/orlandos-nl/Citadel)：Swift SSH 客户端
- XcodeGen

## 说明

- 应用只在本机和路由器之间传输数据，不经过云端。
- 接受路由器 SSH 主机密钥，适合可信局域网。
- 本地 HTTP 控制面板需要 ATS 例外，Info.plist 已配置。
- 这是原生重写，不是 Android APK 的包装。
