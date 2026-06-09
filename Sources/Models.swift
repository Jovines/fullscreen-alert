import Foundation

// MARK: - 通知等级

/// 通知等级：compact = 屏幕中央横向小卡（默认，不打扰）；full = 全屏黑幕大卡（强提醒）
enum AlertLevel: String, Codable {
    case compact
    case full
}

// MARK: - 请求模型

/// 客户端发送的通知请求
struct AlertRequest: Codable {
    let id: String              // 唯一标识
    let title: String           // 标题
    let message: String         // 消息内容
    let sound: String?          // 提示音
    let timestamp: String       // 请求时间
    let level: AlertLevel?      // 通知等级（默认走 Config.defaultLevel）

    init(title: String, message: String, sound: String? = nil, level: AlertLevel? = nil) {
        self.id = UUID().uuidString
        self.title = title
        self.message = message
        self.sound = sound
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.level = level
    }
}

/// 守护进程命令
enum DaemonCommand: String, Codable {
    case show = "show"          // 显示通知
    case close = "close"        // 关闭指定通知
    case closeAll = "closeAll"  // 关闭所有通知
    case list = "list"          // 列出所有通知
    case ping = "ping"          // 心跳检测
    case dump = "dump"          // 把当前窗口快照写入临时文件（调试用）
    case upgrade = "upgrade"    // 把指定 compact 通知升级为 full（调试/快捷键备用）
    case simulateHover = "simulateHover"  // 模拟鼠标移到屏幕指定坐标（测试用）
    case simulateRightClick = "simulateRightClick"  // 模拟在屏幕指定坐标右键（测试用）
}

/// 客户端发送的命令包
struct CommandPacket: Codable {
    let command: DaemonCommand
    let request: AlertRequest?
    let alertId: String?        // 用于 close 命令
    let mouseX: CGFloat?        // simulateHover
    let mouseY: CGFloat?

    init(command: DaemonCommand, request: AlertRequest? = nil, alertId: String? = nil, mouseX: CGFloat? = nil, mouseY: CGFloat? = nil) {
        self.command = command
        self.request = request
        self.alertId = alertId
        self.mouseX = mouseX
        self.mouseY = mouseY
    }
}

/// 守护进程响应
struct DaemonResponse: Codable {
    let success: Bool
    let message: String?
    let alertIds: [String]?     // 用于 list 命令
    var version: String?        // 用于 ping 命令返回守护进程版本

    init(success: Bool, message: String?, alertIds: [String]?, version: String? = nil) {
        self.success = success
        self.message = message
        self.alertIds = alertIds
        self.version = version
    }
}

// MARK: - 内部模型

/// 解析后的消息内容
struct ParsedMessage {
    let prompt: String?
    let response: String?
    let metaLines: [String]

    init(message: String) {
        let parts = message.components(separatedBy: "|||")
        var prompt: String?
        var response: String?
        var metaLines: [String] = []

        for (index, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("路径:") || trimmed.hasPrefix("分支:") || trimmed.hasPrefix("模型:") ||
               trimmed.hasPrefix("耗时:") || trimmed.hasPrefix("Token:") || trimmed.hasPrefix("会话:") ||
               trimmed.hasPrefix("引擎:") {
                metaLines.append(trimmed)
            } else if !trimmed.isEmpty {
                if index == 0 {
                    prompt = trimmed
                } else if index == 1 {
                    response = part.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        self.prompt = prompt
        self.response = response
        self.metaLines = metaLines
    }
}

/// 通知信息（用于内部管理）
struct AlertInfo {
    let id: String
    let request: AlertRequest
    let parsedMessage: ParsedMessage
    var frame: NSRect = NSRect.zero
    var isReady: Bool = false

    init(request: AlertRequest) {
        self.id = request.id
        self.request = request
        self.parsedMessage = ParsedMessage(message: request.message)
    }
}
