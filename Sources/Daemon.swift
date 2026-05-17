import Foundation

// MARK: - 守护进程

class Daemon {
    static let shared = Daemon()

    private var serverSocket: Int32 = -1
    private var isRunning = false
    private var idleTimer: Timer?
    private let alertManager = AlertManager.shared

    private init() {}

    // MARK: - 启动/停止

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // 写入 PID 文件
        writePidFile()

        // 创建 Socket
        guard setupSocket() else {
            // 无法创建 socket，说明已有守护进程在运行，直接退出
            exit(0)
        }

        // 设置空闲超时
        resetIdleTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }

        removePidFile()
        removeSocketFile()

        idleTimer?.invalidate()
        idleTimer = nil

        exit(0)
    }

    // MARK: - Socket 管理

    @discardableResult
    private func setupSocket() -> Bool {
        // 尝试连接已有 socket，如果成功说明已有守护进程在运行
        let testSock = socket(AF_UNIX, SOCK_STREAM, 0)
        if testSock >= 0 {
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            Constants.socketPath.withCString { path in
                strcpy(&addr.sun_path.0, path)
            }
            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    Darwin.connect(testSock, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            close(testSock)
            if connectResult == 0 {
                // 已有守护进程在运行
                return false
            }
        }

        // 移除旧的 socket 文件
        removeSocketFile()

        // 创建 socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return false }

        // 绑定地址
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let socketPath = Constants.socketPath
        socketPath.withCString { path in
            strcpy(&addr.sun_path.0, path)
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            close(serverSocket)
            return false
        }

        // 监听
        guard listen(serverSocket, 10) == 0 else {
            close(serverSocket)
            return false
        }

        // 使用 FileHandle 监听 socket
        let fileHandle = FileHandle(fileDescriptor: serverSocket, closeOnDealloc: false)
        fileHandle.waitForDataInBackgroundAndNotify()

        NotificationCenter.default.addObserver(forName: .NSFileHandleDataAvailable, object: fileHandle, queue: nil) { [weak self] _ in
            self?.acceptConnection()
            fileHandle.waitForDataInBackgroundAndNotify()
        }

        return true
    }

    private func acceptConnection() {
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.accept(serverSocket, sockPtr, &clientLen)
            }
        }

        guard clientSocket >= 0 else { return }

        // 读取请求
        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)

        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            handleRequest(data, clientSocket: clientSocket)
        }

        close(clientSocket)
    }

    // MARK: - 请求处理

    private func handleRequest(_ data: Data, clientSocket: Int32) {
        resetIdleTimer()

        guard let packet = try? JSONDecoder().decode(CommandPacket.self, from: data) else {
            sendResponse(success: false, message: "Invalid request", to: clientSocket)
            return
        }

        var response = DaemonResponse(success: true, message: nil, alertIds: nil)

        switch packet.command {
        case .show:
            if let request = packet.request {
                alertManager.showAlert(request)
                response = DaemonResponse(success: true, message: "Alert shown", alertIds: nil)
            }
        case .close:
            if let alertId = packet.alertId {
                alertManager.closeAlert(alertId)
                response = DaemonResponse(success: true, message: "Alert closed", alertIds: nil)
            }
        case .closeAll:
            alertManager.closeAllAlerts()
            response = DaemonResponse(success: true, message: "All alerts closed", alertIds: nil)
        case .list:
            let ids = alertManager.listAlerts()
            response = DaemonResponse(success: true, message: nil, alertIds: ids)
        case .ping:
            response = DaemonResponse(success: true, message: "Pong", alertIds: nil)
        }

        sendResponse(success: response.success, message: response.message, alertIds: response.alertIds, to: clientSocket)
    }

    private func sendResponse(success: Bool, message: String?, alertIds: [String]? = nil, to socket: Int32) {
        let response = DaemonResponse(success: success, message: message, alertIds: alertIds)
        guard let data = try? JSONEncoder().encode(response) else { return }
        _ = send(socket, data.withUnsafeBytes { ptr in ptr.baseAddress }, data.count, 0)
    }

    // MARK: - PID 和文件管理

    private func writePidFile() {
        let pid = getpid()
        try? "\(pid)".write(toFile: Constants.pidFilePath, atomically: true, encoding: .utf8)
    }

    private func removePidFile() {
        try? FileManager.default.removeItem(atPath: Constants.pidFilePath)
    }

    private func removeSocketFile() {
        try? FileManager.default.removeItem(atPath: Constants.socketPath)
    }

    // MARK: - 空闲超时

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        let timeout = Config.load().daemonIdleTimeout ?? Constants.daemonIdleTimeout
        idleTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            if self?.alertManager.hasAlerts() == false {
                self?.stop()
            } else {
                self?.resetIdleTimer()
            }
        }
    }

    // MARK: - 检查守护进程是否运行

    static func isRunning() -> Bool {
        guard let pidString = try? String(contentsOfFile: Constants.pidFilePath, encoding: .utf8),
              let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }

        // 检查进程是否存在
        return kill(pid, 0) == 0
    }
}
