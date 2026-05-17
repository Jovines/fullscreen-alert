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
            // socket 可连接，守护进程已在运行
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

    选项:
      --timeout <秒>     自动关闭超时时间
      --sound <名称>     提示音（默认: Purr）
                         内置: Glass, Blow, Bottle, Frog, Funk, Pop, Purr, Sosumi, Submarine, Tink
                         静音: none
                         文件: /path/to/sound.wav

    守护进程命令:
      --daemon           作为守护进程运行
      --list             列出所有通知
      --close-all        关闭所有通知

    示例:
      fullscreen-alert "完成" "任务已完成"
      fullscreen-alert "完成" "任务已完成" --sound Pop
      fullscreen-alert --list
      fullscreen-alert --close-all
    """)
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

// 正常的通知请求
let title = args[1]
var message = ""
var timeout: TimeInterval = 0
var soundName: String? = "Purr"

var i = 2
while i < args.count {
    if args[i] == "--timeout" && i + 1 < args.count {
        timeout = TimeInterval(args[i + 1]) ?? 5
        i += 2
    } else if args[i] == "--sound" && i + 1 < args.count {
        soundName = args[i + 1]
        i += 2
    } else if !args[i].starts(with: "--") {
        message = args[i]
        i += 1
    } else {
        i += 1
    }
}

// 创建请求
let request = AlertRequest(title: title, message: message, sound: soundName)

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
