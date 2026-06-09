import Cocoa

// MARK: - AlertManager（管理多个通知）

class AlertManager: NSObject {
    static let shared = AlertManager()

    private var window: NSWindow?
    private var containerView: NSView?
    private var cards: [String: AlertCardView] = [:]
    private var alertOrder: [String] = []         // 全部卡片（包括 compact 与 full）
    private var compactOrder: [String] = []       // 仅 compact，按从左到右
    private var fullOrder: [String] = []          // 仅 full，按出现顺序（顶层是 first）
    private var scrollMonitor: Any?
    private var mouseMovedMonitor: Any?

    private override init() {
        super.init()
    }

    // MARK: - 窗口管理

    private var activeScreen: NSScreen? {
        return window?.screen ?? NSScreen.screens.first
    }

    /// 是否有 full 模式卡片在显示（决定窗口背景与鼠标穿透）
    private var hasFullCard: Bool { return !fullOrder.isEmpty }

    private func ensureWindow() {
        guard window == nil else { return }

        guard let screen = NSScreen.screens.first else { return }
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.alphaValue = 1
        // 默认完全穿透（compact 模式不打扰用户）
        window.ignoresMouseEvents = true

        let containerView = NSView(frame: screen.frame)
        containerView.wantsLayer = true
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.containerView = containerView

        // 右键点击关闭顶层卡片
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleRightClick()
            return event
        }

        // Cmd+C 复制（full 模式 WebView 选中文本）
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 8 {
                self?.handleCopy()
            }
            return event
        }

        // 滚轮拦截：仅 full 模式多卡叠放时强制由顶层处理
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            return self?.handleScrollWheel(event) ?? event
        }

        // 全局鼠标移动监听 — 决定 compact 模式下窗口是否需要接收事件
        // 鼠标进入任意 compact 卡片矩形 -> 解开 ignoresMouseEvents；离开则恢复穿透
        mouseMovedMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            self?.updateMousePassthrough()
        }
        // 同时监听 local（鼠标已经在窗口上时）
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }
    }

    /// 根据当前鼠标位置，决定窗口是否要接收事件
    /// 规则：
    ///  - 有 full 卡片：窗口拦截全屏（不穿透）
    ///  - 仅 compact 卡片：鼠标位于任意 compact 卡片矩形内 -> 不穿透；否则穿透
    private func updateMousePassthrough() {
        guard let window = window else { return }

        if hasFullCard {
            window.ignoresMouseEvents = false
            return
        }

        // 仅 compact 场景
        let mouseLoc = NSEvent.mouseLocation
        var insideAny = false
        for cardId in compactOrder {
            guard let card = cards[cardId] else { continue }
            if card.containsScreenPoint(mouseLoc) {
                insideAny = true
                break
            }
        }
        window.ignoresMouseEvents = !insideAny

        // 通知所有 compact 卡片更新 hover 状态（边框高亮 / hover-out 关闭）
        for cardId in compactOrder {
            cards[cardId]?.compactHandleGlobalMouseMoved()
        }
    }

    // MARK: - 显示通知

    func showAlert(_ request: AlertRequest) {
        DispatchQueue.main.async { [weak self] in
            self?._showAlert(request)
        }
    }

    private func _showAlert(_ request: AlertRequest) {
        let level = request.level ?? Config.load().defaultLevel ?? Constants.defaultLevel
        print("AlertManager._showAlert: title=\(request.title) level=\(level.rawValue)")
        ensureWindow()

        let alertInfo = AlertInfo(request: request)

        if level == .compact {
            let card = AlertCardView(alertInfo: alertInfo, maxWidth: Constants.compactCardWidth, level: .compact)
            card.onReady = { [weak self] in
                guard let self = self else { return }
                self.updateMousePassthrough()
            }
            card.onClose = { [weak self] in
                self?.closeAlert(request.id)
            }
            card.onUpgrade = { [weak self] in
                self?.upgradeToFull(request)
            }

            cards[request.id] = card
            alertOrder.append(request.id)
            compactOrder.append(request.id)

            containerView?.addSubview(card)
            relayoutCompactCards(animated: true)
            return
        }

        // ===== Full 模式 =====
        let config = Config.load()
        let screenMargin = config.screenMargin ?? Constants.screenMargin
        let maxCardWidth = config.cardWidth ?? Constants.cardWidth
        let cardWidth = min(
            (activeScreen?.frame.width ?? 1000) - screenMargin * 2,
            maxCardWidth
        )

        let card = AlertCardView(alertInfo: alertInfo, maxWidth: cardWidth, level: .full)

        if let screen = activeScreen {
            let visibleFrame = screen.visibleFrame
            let visibleMinY = visibleFrame.origin.y - screen.frame.origin.y
            var cardFrame = card.frame
            cardFrame.origin.x = (screen.frame.width - cardFrame.width) / 2
            cardFrame.origin.y = visibleMinY + (visibleFrame.height - cardFrame.height) / 2
            card.frame = cardFrame
        }

        card.onReady = { [weak self] in
            self?.applyWindowBackgroundForLevel()
            self?.updateMousePassthrough()
        }
        card.onClose = { [weak self] in
            self?.closeAlert(request.id)
        }

        cards[request.id] = card
        alertOrder.append(request.id)
        fullOrder.append(request.id)

        containerView?.addSubview(card)
        applyWindowBackgroundForLevel()
        relayoutFullCards()
    }

    /// 根据当前是否有 full 卡片，决定窗口是否显示半透明黑幕
    private func applyWindowBackgroundForLevel() {
        guard let window = window else { return }
        if hasFullCard {
            window.backgroundColor = NSColor.black.withAlphaComponent(0.5)
        } else {
            window.backgroundColor = .clear
        }
    }

    // MARK: - 升级：compact -> full

    /// 把一条 compact 通知升级为 full 模式（保留原 id）
    func upgradeToFull(_ request: AlertRequest) {
        DispatchQueue.main.async { [weak self] in
            self?._upgradeToFull(request)
        }
    }

    /// 通过 id 升级（外部 socket 命令使用）
    func upgradeAlertById(_ id: String) -> Bool {
        guard let card = cards[id], card.level == .compact else { return false }
        card.markUpgrading()
        let req = card.alertRequest
        upgradeToFull(req)
        return true
    }

    private func _upgradeToFull(_ request: AlertRequest) {
        // 原 compact 卡片直接移除（不走淡出动画，避免与 full 入场重叠）
        guard let oldCard = cards[request.id], oldCard.level == .compact else { return }
        oldCard.removeFromSuperview()
        cards.removeValue(forKey: request.id)
        alertOrder.removeAll { $0 == request.id }
        compactOrder.removeAll { $0 == request.id }

        // 用同一 id 走 full 路径
        let alertInfo = AlertInfo(request: request)
        let config = Config.load()
        let screenMargin = config.screenMargin ?? Constants.screenMargin
        let maxCardWidth = config.cardWidth ?? Constants.cardWidth
        let cardWidth = min(
            (activeScreen?.frame.width ?? 1000) - screenMargin * 2,
            maxCardWidth
        )

        let card = AlertCardView(alertInfo: alertInfo, maxWidth: cardWidth, level: .full)

        if let screen = activeScreen {
            let visibleFrame = screen.visibleFrame
            let visibleMinY = visibleFrame.origin.y - screen.frame.origin.y
            var cardFrame = card.frame
            cardFrame.origin.x = (screen.frame.width - cardFrame.width) / 2
            cardFrame.origin.y = visibleMinY + (visibleFrame.height - cardFrame.height) / 2
            card.frame = cardFrame
        }

        card.onReady = { [weak self] in
            self?.applyWindowBackgroundForLevel()
            self?.updateMousePassthrough()
        }
        card.onClose = { [weak self] in
            self?.closeAlert(request.id)
        }

        cards[request.id] = card
        alertOrder.append(request.id)
        fullOrder.append(request.id)

        containerView?.addSubview(card)
        applyWindowBackgroundForLevel()
        updateMousePassthrough()
        relayoutFullCards()

        // 剩余 compact 卡片需要重排（因为少了一张）
        if !compactOrder.isEmpty {
            relayoutCompactCards(animated: true)
        }
    }

    // MARK: - Compact 布局：横向居中排列

    private func relayoutCompactCards(animated: Bool) {
        guard let screen = activeScreen else { return }
        let visibleFrame = screen.visibleFrame
        let visibleMinY = visibleFrame.origin.y - screen.frame.origin.y
        let visibleMaxY = visibleMinY + visibleFrame.height
        let screenCenterX = screen.frame.width / 2
        let topMargin = Config.load().compactTopMargin ?? Constants.compactTopMargin

        // 找出所有 compact 卡片的最大高度（用于垂直对齐）
        var maxHeight: CGFloat = 0
        var widths: [CGFloat] = []
        for cardId in compactOrder {
            guard let card = cards[cardId] else { continue }
            maxHeight = max(maxHeight, card.frame.height)
            widths.append(card.frame.width)
        }

        let spacing = Config.load().compactHorizontalSpacing ?? Constants.compactHorizontalSpacing
        let totalWidth = widths.reduce(0, +) + spacing * CGFloat(max(0, widths.count - 1))
        var currentX = screenCenterX - totalWidth / 2

        // 顶部基线：visibleFrame 顶边 - topMargin - maxHeight
        let groupBaseY = visibleMaxY - topMargin - maxHeight

        print("=== relayoutCompactCards count=\(compactOrder.count) totalWidth=\(totalWidth) groupBaseY=\(groupBaseY) ===")

        let runUpdates: () -> Void = { [weak self] in
            guard let self = self else { return }
            for (index, cardId) in self.compactOrder.enumerated() {
                guard let card = self.cards[cardId] else { continue }
                let cardWidth = card.frame.width
                let cardHeight = card.frame.height
                let x = currentX
                // 不同卡片高度不同时，整组顶边对齐（更符合视觉）
                let y = groupBaseY + (maxHeight - cardHeight)
                let target = NSRect(x: x, y: y, width: cardWidth, height: cardHeight)

                if animated {
                    card.animator().frame = target
                } else {
                    card.frame = target
                }
                card.setIndexBadge(index + 1)
                print("  card[\(index)] id=\(cardId.prefix(8)) frame=\(target)")

                currentX += cardWidth + spacing
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
                runUpdates()
            }
        } else {
            runUpdates()
        }
        fflush(stdout)
    }

    // MARK: - Full 布局（原逻辑）

    private var previousTopCardId: String?

    private func relayoutFullCards() {
        guard let screen = activeScreen else { return }
        let visibleFrame = screen.visibleFrame
        let visibleMinY = visibleFrame.origin.y - screen.frame.origin.y
        let screenCenterX = screen.frame.width / 2
        let screenCenterY = visibleMinY + visibleFrame.height / 2

        for (index, cardId) in fullOrder.enumerated() {
            guard let card = cards[cardId] else { continue }
            let isTop = (index == 0)
            card.setAcceptsPointerEvents(isTop)
            card.setShouldTrackMouse(false)
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)

            for (index, cardId) in fullOrder.enumerated() {
                guard let card = cards[cardId] else { continue }
                let isTop = (index == 0)

                card.layer?.zPosition = CGFloat(fullOrder.count - index)

                if isTop {
                    self.containerView?.addSubview(card, positioned: .above, relativeTo: nil)
                }

                card.setPendingCount(0)

                let cardWidth = card.frame.width
                let cardHeight = card.frame.height
                let baseX = screenCenterX - cardWidth / 2
                let baseY = screenCenterY - cardHeight / 2

                if isTop {
                    card.layer?.transform = CATransform3DIdentity
                    card.animator().frame = NSRect(x: baseX, y: baseY, width: cardWidth, height: cardHeight)
                } else {
                    let xOffset = CGFloat(index) * -100
                    let yOffset = CGFloat(index) * -50
                    let newX = baseX + xOffset
                    let newY = baseY + yOffset
                    card.animator().frame = NSRect(x: newX, y: newY, width: cardWidth, height: cardHeight)
                    card.layer?.transform = CATransform3DIdentity
                }
            }
        } completionHandler: { [weak self] in
            guard let self = self, let topCardId = self.fullOrder.first,
                  let topCard = self.cards[topCardId] else { return }
            if let prevId = self.previousTopCardId, prevId != topCardId {
                topCard.setProtectionDelay(0.2)
            }
            topCard.setAcceptsPointerEvents(true)
            topCard.setShouldTrackMouse(true)
        }

        previousTopCardId = fullOrder.first
        fflush(stdout)
    }

    // MARK: - 关闭通知

    func closeAlert(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            self?._closeAlert(id)
        }
    }

    private func _closeAlert(_ id: String) {
        guard let card = cards[id] else { return }
        let wasFull = (card.level == .full)

        card.animateOut { [weak self] in
            guard let self = self else { return }
            card.removeFromSuperview()
            self.cards.removeValue(forKey: id)
            self.alertOrder.removeAll { $0 == id }
            self.compactOrder.removeAll { $0 == id }
            self.fullOrder.removeAll { $0 == id }

            if self.cards.isEmpty {
                self.window?.animator().alphaValue = 0
                self.window?.backgroundColor = .clear
                self.window?.ignoresMouseEvents = true
                // 让窗口下次再 ensureWindow 时复用（不销毁，避免视觉闪烁）
                self.window?.alphaValue = 1
            } else {
                if wasFull {
                    self.applyWindowBackgroundForLevel()
                    if !self.fullOrder.isEmpty {
                        self.relayoutFullCards()
                    }
                }
                if !self.compactOrder.isEmpty {
                    self.relayoutCompactCards(animated: true)
                }
                self.updateMousePassthrough()
            }
        }
    }

    func closeAllAlerts() {
        DispatchQueue.main.async { [weak self] in
            for cardId in self?.alertOrder ?? [] {
                self?._closeAlert(cardId)
            }
        }
    }

    // MARK: - 事件处理

    private func handleRightClick() {
        // 优先关闭鼠标所在的 compact 卡片；否则关 full 顶层
        let mouseLoc = NSEvent.mouseLocation
        for cardId in compactOrder {
            if let card = cards[cardId], card.containsScreenPoint(mouseLoc) {
                closeAlert(cardId)
                return
            }
        }
        guard let topCardId = fullOrder.first else { return }
        closeAlert(topCardId)
    }

    private func handleCopy() {
        for cardId in fullOrder {
            if let card = cards[cardId] {
                card.handleCopy()
            }
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard fullOrder.count > 1,
              let topCardId = fullOrder.first,
              let topCard = cards[topCardId] else {
            return event
        }

        let mouseLocation = NSEvent.mouseLocation
        let isOverAnyCard = fullOrder.contains { cardId in
            cards[cardId]?.containsScreenPoint(mouseLocation) == true
        }

        guard isOverAnyCard else { return event }

        if topCard.forwardScrollWheelToWebView(event) {
            return nil
        }

        return event
    }

    // MARK: - 查询

    func listAlerts() -> [String] {
        return alertOrder
    }

    func hasAlerts() -> Bool {
        return !cards.isEmpty
    }

    /// 把当前 containerView 渲染成 PNG 写到指定路径（不需要系统权限）
    /// 用于自动化验证 UI 布局
    func dumpWindowSnapshot(to path: String) -> Bool {
        guard let view = containerView else { return false }
        let bounds = view.bounds
        guard let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }

    /// 输出当前所有卡片在屏幕坐标的位置（调试日志）
    func debugDescribeLayout() -> String {
        var lines: [String] = []
        lines.append("== Layout snapshot ==")
        lines.append("hasFullCard=\(hasFullCard) compactCount=\(compactOrder.count) fullCount=\(fullOrder.count)")
        if let win = window {
            lines.append("window.frame=\(win.frame) ignoresMouseEvents=\(win.ignoresMouseEvents)")
        }
        if let screen = activeScreen {
            lines.append("screen.frame=\(screen.frame) visibleFrame=\(screen.visibleFrame)")
        }
        for (idx, id) in compactOrder.enumerated() {
            if let card = cards[id] {
                lines.append("compact[\(idx)] id=\(id.prefix(8)) frame=\(card.frame)")
                lines.append("            \(card.debugHoverState)")
            }
        }
        for (idx, id) in fullOrder.enumerated() {
            if let card = cards[id] {
                lines.append("full[\(idx)] id=\(id.prefix(8)) frame=\(card.frame)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 测试用：模拟鼠标移动到屏幕指定坐标，驱动所有 compact 卡片的 hover 检测
    /// 返回当前 hover 后的卡片状态描述
    func simulateMouseAt(_ point: NSPoint) -> String {
        // 与正常 hover 保持一致：先更新 ignoresMouseEvents（这里只是模拟，不真实修改）
        for cardId in compactOrder {
            cards[cardId]?.compactHandleMouseAt(point)
        }
        return debugDescribeLayout()
    }

    /// 测试用：在指定屏幕坐标模拟一次右键点击 — 命中哪个卡就关哪个
    func simulateRightClickAt(_ point: NSPoint) -> String {
        for cardId in compactOrder {
            if let card = cards[cardId], card.containsScreenPoint(point) {
                closeAlert(cardId)
                return "right-click closed compact \(cardId)"
            }
        }
        if let topId = fullOrder.first {
            closeAlert(topId)
            return "right-click closed full top \(topId)"
        }
        return "right-click hit nothing"
    }
}
