import Cocoa

// MARK: - 客户端

func sendCommandToDaemon(_ packet: CommandPacket) -> DaemonResponse? {
    let socketPath = Constants.socketPath

    // 创建 socket
    let sock = socket(AF_UNIX, SOCK_STREAM, 0)
    guard sock >= 0 else {
        return DaemonResponse(success: false, message: "Failed to create socket", alertIds: nil)
    }
    defer { close(sock) }

    // 连接
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    socketPath.withCString { path in
        strcpy(&addr.sun_path.0, path)
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            Darwin.connect(sock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        return DaemonResponse(success: false, message: "Failed to connect to daemon", alertIds: nil)
    }

    // 发送请求
    guard let data = try? JSONEncoder().encode(packet) else {
        return DaemonResponse(success: false, message: "Failed to encode request", alertIds: nil)
    }

    _ = send(sock, data.withUnsafeBytes { ptr in ptr.baseAddress }, data.count, 0)

    // 接收响应
    var buffer = [UInt8](repeating: 0, count: 4096)
    let bytesRead = recv(sock, &buffer, buffer.count, 0)

    guard bytesRead > 0 else {
        return DaemonResponse(success: true, message: nil, alertIds: nil)
    }

    let responseData = Data(bytes: buffer, count: bytesRead)
    return try? JSONDecoder().decode(DaemonResponse.self, from: responseData)
}

func killOldDaemon() {
    // 读取 PID 文件
    guard let pidString = try? String(contentsOfFile: Constants.pidFilePath, encoding: .utf8),
          let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return
    }

    // 杀掉旧进程
    kill(pid, SIGTERM)

    // 等待进程退出（最多 1 秒）
    let deadline = Date().addingTimeInterval(1.0)
    while kill(pid, 0) == 0 && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.1)
    }

    // 清理残留文件
    try? FileManager.default.removeItem(atPath: Constants.pidFilePath)
    try? FileManager.default.removeItem(atPath: Constants.socketPath)
}

func startDaemonIfNeeded() {
    // 首先尝试连接 socket，如果成功说明守护进程已在运行
    let socketPath = Constants.socketPath
    let testSock = socket(AF_UNIX, SOCK_STREAM, 0)
    if testSock >= 0 {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { path in
            strcpy(&addr.sun_path.0, path)
        }
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(testSock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(testSock)
        if connectResult == 0 {
            // 守护进程已在运行，检查版本是否一致
            let packet = CommandPacket(command: .ping, request: nil, alertId: nil)
            if let response = sendCommandToDaemon(packet),
               let daemonVersion = response.version,
               daemonVersion != Constants.version {
                // 版本不一致，杀掉旧进程，启动新的
                killOldDaemon()
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/fullscreen-alert")
                process.arguments = ["--daemon"]
                process.environment = ProcessInfo.processInfo.environment
                do {
                    try process.run()
                    Thread.sleep(forTimeInterval: 0.5)
                } catch {
                    print("Failed to restart daemon: \(error)")
                }
                return
            }
            // 版本一致或无法检测，复用现有守护进程
            return
        }
    }

    // 再检查 PID 文件（双重检查）
    if Daemon.isRunning() {
        // 等待一下让 socket 创建完成
        Thread.sleep(forTimeInterval: 0.3)
        return
    }

    // 启动守护进程
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/fullscreen-alert")
    process.arguments = ["--daemon"]
    process.environment = ProcessInfo.processInfo.environment

    do {
        try process.run()
        // 等待 socket 创建
        Thread.sleep(forTimeInterval: 0.5)
    } catch {
        print("Failed to start daemon: \(error)")
    }
}

// MARK: - 主入口

let args = CommandLine.arguments

// 检查是否是守护进程模式
if args.count > 1 && args[1] == "--daemon" {
    // 守护进程模式
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let delegate = DaemonAppDelegate()
    app.delegate = delegate

    app.run()
    exit(0)
}

// 检查帮助
if args.count < 2 || args.contains("--help") || args.contains("-h") {
    print("""
    fullscreen-alert - macOS 全屏提示工具

    用法: fullscreen-alert <标题> [消息] [选项]

    消息体支持用 ||| 分隔多段：
      <prompt>|||<response>|||<meta1>|||<meta2>...
        - prompt：提问/简介，带左侧蓝色竖线
        - response：Markdown 内容，full 模式下用 WebView 渲染（含代码高亮）
        - meta：以 "路径:/分支:/模型:/耗时:/Token:/会话:/引擎:" 开头的元信息行

    选项:
      --level <等级>     compact（小卡片，屏幕顶部横向，默认）| full（全屏黑幕大卡）
      --priority <级别>  high 等价于 --level full
      --timeout <秒>     自动关闭超时时间
      --sound <名称>     提示音（默认: Purr）
                         内置: Glass, Blow, Bottle, Frog, Funk, Pop, Purr, Sosumi, Submarine, Tink
                         静音: none
                         文件: /path/to/sound.wav

    管理命令:
      disable                       临时禁用全屏提示
      enable                        重新启用全屏提示
      --list                        列出所有 alert id
      --close <id>                  按 id 关闭单条
      --close-all                   关闭所有通知
      --upgrade <id>                把指定 compact 升级为 full（等价左键点击）

    调试 / 自动化测试:
      --daemon                      作为守护进程运行（客户端会自动拉起，一般不需要手动）
      --dump [path]                 把当前窗口快照存为 PNG，并打印 layout snapshot
                                    默认路径: /tmp/fullscreen-alert-dump.png
      --simulate-hover <x> <y>      模拟鼠标到屏幕坐标 (x,y)，驱动 compact 卡 hover 检测
      --simulate-rightclick <x> <y> 模拟在 (x,y) 右键 — 命中 compact 关该卡，否则关 full 顶层

    示例:
      fullscreen-alert "完成" "任务已完成"
      fullscreen-alert "完成" "任务已完成" --level full --sound Pop
      fullscreen-alert "构建" "Build OK|||## 编译报告\\n- 耗时 2m 30s\\n\\n\\`\\`\\`swift\\nlet x=1\\n\\`\\`\\`|||路径: /repo|||分支: main"
      fullscreen-alert --list
      fullscreen-alert --close <id>
      fullscreen-alert --close-all
    """)
    exit(0)
}

// 禁用/启用命令
if args.count == 2 && args[1] == "disable" {
    var config = Config.load()
    config.disabled = true
    config.save()
    print("fullscreen-alert 已禁用")
    exit(0)
}

if args.count == 2 && args[1] == "enable" {
    var config = Config.load()
    config.disabled = false
    config.save()
    print("fullscreen-alert 已启用")
    exit(0)
}

// 检查其他命令
if args.contains("--list") {
    startDaemonIfNeeded()
    let packet = CommandPacket(command: .list, request: nil, alertId: nil)
    if let response = sendCommandToDaemon(packet), let ids = response.alertIds {
        print("Active alerts: \(ids.count)")
        for id in ids {
            print("  - \(id)")
        }
    } else {
        print("No active alerts or daemon not running")
    }
    exit(0)
}

if args.contains("--close-all") {
    startDaemonIfNeeded()
    let packet = CommandPacket(command: .closeAll, request: nil, alertId: nil)
    _ = sendCommandToDaemon(packet)
    print("All alerts closed")
    exit(0)
}

if args.contains("--close") {
    startDaemonIfNeeded()
    guard let idx = args.firstIndex(of: "--close"), idx + 1 < args.count else {
        print("Usage: fullscreen-alert --close <alert-id>")
        exit(1)
    }
    let alertId = args[idx + 1]
    let packet = CommandPacket(command: .close, request: nil, alertId: alertId)
    if let response = sendCommandToDaemon(packet) {
        print(response.message ?? "")
        exit(response.success ? 0 : 1)
    }
    exit(1)
}

if args.contains("--dump") {
    startDaemonIfNeeded()
    var dumpPath = "/tmp/fullscreen-alert-dump.png"
    if let idx = args.firstIndex(of: "--dump"), idx + 1 < args.count, !args[idx + 1].starts(with: "--") {
        dumpPath = args[idx + 1]
    }
    let packet = CommandPacket(command: .dump, request: nil, alertId: dumpPath)
    if let response = sendCommandToDaemon(packet) {
        print(response.message ?? "")
        exit(response.success ? 0 : 1)
    }
    exit(1)
}

if args.contains("--upgrade") {
    startDaemonIfNeeded()
    guard let idx = args.firstIndex(of: "--upgrade"), idx + 1 < args.count else {
        print("Usage: fullscreen-alert --upgrade <alert-id>")
        exit(1)
    }
    let alertId = args[idx + 1]
    let packet = CommandPacket(command: .upgrade, request: nil, alertId: alertId)
    if let response = sendCommandToDaemon(packet) {
        print(response.message ?? "")
        exit(response.success ? 0 : 1)
    }
    exit(1)
}

if args.contains("--simulate-hover") {
    startDaemonIfNeeded()
    guard let idx = args.firstIndex(of: "--simulate-hover"), idx + 2 < args.count,
          let x = Double(args[idx + 1]), let y = Double(args[idx + 2]) else {
        print("Usage: fullscreen-alert --simulate-hover <x> <y>")
        exit(1)
    }
    let packet = CommandPacket(command: .simulateHover, request: nil, alertId: nil, mouseX: CGFloat(x), mouseY: CGFloat(y))
    if let response = sendCommandToDaemon(packet) {
        print(response.message ?? "")
        exit(response.success ? 0 : 1)
    }
    exit(1)
}

if args.contains("--simulate-rightclick") {
    startDaemonIfNeeded()
    guard let idx = args.firstIndex(of: "--simulate-rightclick"), idx + 2 < args.count,
          let x = Double(args[idx + 1]), let y = Double(args[idx + 2]) else {
        print("Usage: fullscreen-alert --simulate-rightclick <x> <y>")
        exit(1)
    }
    let packet = CommandPacket(command: .simulateRightClick, request: nil, alertId: nil, mouseX: CGFloat(x), mouseY: CGFloat(y))
    if let response = sendCommandToDaemon(packet) {
        print(response.message ?? "")
        exit(response.success ? 0 : 1)
    }
    exit(1)
}

// 正常的通知请求 — 先检查是否已禁用
let config = Config.load()
guard !config.disabled else { exit(0) }

let title = args[1]
var message = ""
var timeout: TimeInterval = 0
var soundName: String? = "Purr"
var level: AlertLevel? = nil

var i = 2
while i < args.count {
    if args[i] == "--timeout" && i + 1 < args.count {
        timeout = TimeInterval(args[i + 1]) ?? 5
        i += 2
    } else if args[i] == "--sound" && i + 1 < args.count {
        soundName = args[i + 1]
        i += 2
    } else if args[i] == "--level" && i + 1 < args.count {
        level = AlertLevel(rawValue: args[i + 1].lowercased())
        i += 2
    } else if args[i] == "--priority" && i + 1 < args.count {
        if args[i + 1].lowercased() == "high" {
            level = .full
        }
        i += 2
    } else if !args[i].starts(with: "--") {
        message = args[i]
        i += 1
    } else {
        i += 1
    }
}

// 创建请求
let request = AlertRequest(title: title, message: message, sound: soundName, level: level)

// 确保守护进程运行
startDaemonIfNeeded()

// 发送请求
let packet = CommandPacket(command: .show, request: request, alertId: nil)
if let response = sendCommandToDaemon(packet) {
    if response.success {
        // 成功，静默退出
    } else {
        print("Error: \(response.message ?? "Unknown error")")
    }
} else {
    print("Failed to send request to daemon")
}

exit(0)

// MARK: - Daemon App Delegate

class DaemonAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("DaemonAppDelegate.applicationDidFinishLaunching")
        fflush(stdout)
        Daemon.shared.start()
        print("Daemon.shared.start() returned")
        fflush(stdout)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
