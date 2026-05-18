import Cocoa

// MARK: - AlertManager（管理多个通知）

class AlertManager: NSObject {
    static let shared = AlertManager()

    private var window: NSWindow?
    private var containerView: NSView?
    private var cards: [String: AlertCardView] = [:]
    private var alertOrder: [String] = []
    private var scrollMonitor: Any?

    private override init() {
        super.init()
    }

    // MARK: - 窗口管理

    private func ensureWindow() {
        guard window == nil else { return }

        guard let screen = NSScreen.main else { return }
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.backgroundColor = NSColor.black.withAlphaComponent(0.5)
        window.isOpaque = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.alphaValue = 0

        let containerView = NSView(frame: screen.frame)
        containerView.wantsLayer = true
        window.contentView = containerView
        window.makeKeyAndOrderFront(nil)

        self.window = window
        self.containerView = containerView

        // 右键点击关闭
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleRightClick()
            return event
        }

        // Cmd+C 复制
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.modifierFlags.contains(.command) && event.keyCode == 8 {
                self?.handleCopy()
            }
            return event
        }

        // 触控板/滚轮事件要强制由最上层通知处理。
        // WKWebView 有自己的滚动响应链；仅靠 NSView.hitTest / layer.zPosition 在多 WebView 叠放时不可靠。
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            return self?.handleScrollWheel(event) ?? event
        }
    }

    // MARK: - 显示通知

    func showAlert(_ request: AlertRequest) {
        DispatchQueue.main.async { [weak self] in
            self?._showAlert(request)
        }
    }

    private func _showAlert(_ request: AlertRequest) {
        print("AlertManager._showAlert called: \(request.title)")
        ensureWindow()
        print("Window ensured: \(window != nil)")

        // 确保窗口接收鼠标事件
        window?.ignoresMouseEvents = false

        let alertInfo = AlertInfo(request: request)
        let config = Config.load()
        let screenMargin = config.screenMargin ?? Constants.screenMargin
        let maxCardWidth = config.cardWidth ?? Constants.cardWidth
        let cardWidth = min(
            (NSScreen.main?.frame.width ?? 1000) - screenMargin * 2,
            maxCardWidth
        )
        print("Card width: \(cardWidth)")

        let card = AlertCardView(alertInfo: alertInfo, maxWidth: cardWidth)
        print("Card created: \(card.frame)")

        // 设置卡片居中位置
        print("NSScreen.main: \(NSScreen.main != nil)")
        if let screen = NSScreen.main {
            print("Screen frame: \(screen.frame)")
            var cardFrame = card.frame
            cardFrame.origin.x = (screen.frame.width - cardFrame.width) / 2
            cardFrame.origin.y = (screen.frame.height - cardFrame.height) / 2
            card.frame = cardFrame
            print("Card centered at: (\(cardFrame.origin.x), \(cardFrame.origin.y))")
        } else {
            print("ERROR: NSScreen.main is nil")
        }

        card.onReady = { [weak self] in
            print("Card onReady")
            self?.window?.animator().alphaValue = 1
        }
        card.onClose = { [weak self] in
            print("Card onClose")
            self?.closeAlert(request.id)
        }

        cards[request.id] = card
        alertOrder.append(request.id)

        containerView?.addSubview(card)
        print("Card added to containerView")
        relayoutCards()
        print("Cards relayouted")
    }

    // MARK: - 布局

    private var previousTopCardId: String?  // 记录之前的顶层卡片

    private func relayoutCards() {
        guard let screen = NSScreen.main else { return }
        let screenCenterX = screen.frame.width / 2
        let screenCenterY = screen.frame.height / 2

        print("=== relayoutCards ===")
        print("Total cards: \(alertOrder.count)")

        // 先禁用所有卡片的鼠标监听
        for (index, cardId) in alertOrder.enumerated() {
            guard let card = cards[cardId] else { continue }
            let isTop = (index == 0)
            // AppKit 的事件命中测试按 subview 顺序，而不是 layer.zPosition。
            // 新通知 addSubview 后虽然视觉上被 zPosition 放到底下，但仍可能先命中它内部的 WKWebView，
            // 导致滚轮滑动新通知。这里显式只让最上层（最早来的）卡片接收鼠标/滚轮事件。
            card.setAcceptsPointerEvents(isTop)
            card.setShouldTrackMouse(false)
        }

        // 使用动画来移动卡片位置
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)

            for (index, cardId) in alertOrder.enumerated() {
                guard let card = cards[cardId] else { continue }

                let isTop = (index == 0)

                // zPosition：越大的越在上面
                card.layer?.zPosition = CGFloat(alertOrder.count - index)

                // 同步 NSView 子视图顺序。AppKit 的命中测试按子视图顺序，不按 layer.zPosition。
                if isTop {
                    self.containerView?.addSubview(card, positioned: .above, relativeTo: nil)
                }

                // 清除徽章
                card.setPendingCount(0)

                let cardWidth = card.frame.width
                let cardHeight = card.frame.height

                // 计算居中位置（所有卡片的基础位置）
                let baseX = screenCenterX - cardWidth / 2
                let baseY = screenCenterY - cardHeight / 2

                if isTop {
                    // 当前卡片（最早来的）：居中
                    card.layer?.transform = CATransform3DIdentity
                    card.animator().frame = NSRect(x: baseX, y: baseY, width: cardWidth, height: cardHeight)
                } else {
                    // 待处理卡片（新来的）：往左移、往下移
                    let xOffset = CGFloat(index) * -100
                    let yOffset = CGFloat(index) * -50

                    let newX = baseX + xOffset
                    let newY = baseY + yOffset

                    card.animator().frame = NSRect(x: newX, y: newY, width: cardWidth, height: cardHeight)
                    card.layer?.transform = CATransform3DIdentity
                }
            }
        } completionHandler: { [weak self] in
            // 动画结束后，激活顶层卡片的鼠标监听
            guard let self = self, let topCardId = self.alertOrder.first,
                  let topCard = self.cards[topCardId] else { return }

            // 如果之前有其他顶层卡片，设置保护期
            if let prevId = self.previousTopCardId, prevId != topCardId {
                topCard.setProtectionDelay(0.2)
            }
            topCard.setAcceptsPointerEvents(true)
            topCard.setShouldTrackMouse(true)
        }

        // 记录当前顶层卡片
        previousTopCardId = alertOrder.first

        fflush(stdout)
    }

    private func totalCardsHeight() -> CGFloat {
        var total: CGFloat = 0
        for cardId in alertOrder {
            if let card = cards[cardId] {
                total += card.cardHeight + (Config.load().cardSpacing ?? Constants.cardSpacing)
            }
        }
        if total > 0 {
            total -= (Config.load().cardSpacing ?? Constants.cardSpacing)  // 移除最后一个间距
        }
        return total
    }

    // MARK: - 关闭通知

    func closeAlert(_ id: String) {
        DispatchQueue.main.async { [weak self] in
            self?._closeAlert(id)
        }
    }

    private func _closeAlert(_ id: String) {
        guard let card = cards[id] else { return }

        card.animateOut { [weak self] in
            card.removeFromSuperview()
            self?.cards.removeValue(forKey: id)
            self?.alertOrder.removeAll { $0 == id }

            if self?.cards.isEmpty == true {
                // 隐藏窗口并让它忽略鼠标事件
                self?.window?.animator().alphaValue = 0
                self?.window?.ignoresMouseEvents = true
            } else {
                self?.relayoutCards()
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
        // 只关闭顶层卡片
        guard let topCardId = alertOrder.first else { return }
        closeAlert(topCardId)
    }

    private func handleCopy() {
        for cardId in alertOrder {
            if let card = cards[cardId] {
                card.handleCopy()
            }
        }
    }

    private func handleScrollWheel(_ event: NSEvent) -> NSEvent? {
        guard alertOrder.count > 1,
              let topCardId = alertOrder.first,
              let topCard = cards[topCardId] else {
            return event
        }

        let mouseLocation = NSEvent.mouseLocation
        let isOverAnyCard = alertOrder.contains { cardId in
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
}
