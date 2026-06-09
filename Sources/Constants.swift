import Foundation

struct Constants {
    // 版本号（客户端与守护进程比对，不一致时自动重启旧进程）
    static let version = "1.3.0"

    // Socket 路径
    static let socketPath = "/tmp/fullscreen-alert.sock"
    static let pidFilePath = "/tmp/fullscreen-alert.pid"

    // 守护进程空闲超时（秒）
    static let daemonIdleTimeout: TimeInterval = 43200  // 12小时

    // 布局常量
    static let screenMargin: CGFloat = 50
    static let cardWidth: CGFloat = 930
    static let cardPadding: CGFloat = 24
    static let innerSpacing: CGFloat = 12
    static let cardSpacing: CGFloat = 20  // 多个卡片之间的间距

    // 高度常量
    static let titleHeight: CGFloat = 36
    static let hintHeight: CGFloat = 18
    static let metaLineHeight: CGFloat = 18
    static let maxResponseHeight: CGFloat = 750
    static let minResponseHeight: CGFloat = 200

    // 表格列宽
    static let maxTableColumnWidth: CGFloat = 450

    // 动画时长
    static let fadeInDuration: TimeInterval = 0.12
    static let fadeOutDuration: TimeInterval = 0.12
    static let scaleAnimationDuration: TimeInterval = 0.16

    // ===== Compact（小卡片）模式 =====
    // 默认等级（compact = 不打扰小卡片，full = 当前的全屏大卡）
    static let defaultLevel: AlertLevel = .compact
    // 单张小卡片宽度
    static let compactCardWidth: CGFloat = 280
    // 小卡片内边距
    static let compactCardPadding: CGFloat = 14
    // 多张小卡片之间的横向间距
    static let compactHorizontalSpacing: CGFloat = 16
    // 小卡片 prompt 最多显示几行
    static let compactPromptMaxLines: Int = 2
    // 小卡片标题区高度
    static let compactTitleHeight: CGFloat = 18
    // 标题与 prompt 之间间距
    static let compactInnerSpacing: CGFloat = 6
    // 左上角编号徽章尺寸
    static let compactBadgeSize: CGFloat = 18
    // 小卡片距屏幕顶部（visibleFrame 顶边）的留白
    static let compactTopMargin: CGFloat = 24
}
