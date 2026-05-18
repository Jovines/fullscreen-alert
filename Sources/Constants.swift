import Foundation

struct Constants {
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
    static let fadeInDuration: TimeInterval = 0.2
    static let fadeOutDuration: TimeInterval = 0.15
    static let scaleAnimationDuration: TimeInterval = 0.25
}
