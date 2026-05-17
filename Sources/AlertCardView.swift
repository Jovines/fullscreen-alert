import Cocoa
import WebKit

// MARK: - 单个通知卡片视图

class AlertCardView: NSView, WKNavigationDelegate {
    private let alertInfo: AlertInfo
    private var webView: WKWebView?
    private var promptHeight: CGFloat = 0
    private var metaHeight: CGFloat = 0
    private var maxResponseHeight: CGFloat = Constants.maxResponseHeight
    private var hasPlayedSound = false
    private var badgeView: NSView?  // 待处理数量徽章

    var onReady: (() -> Void)?
    var onClose: (() -> Void)?

    // 鼠标追踪
    private var isCardReady = false
    private var mouseMonitor: Any?
    private var shouldTrackMouse = true
    private var protectedUntil: Date?  // 保护期结束时间，nil 表示无保护期
    private var isMouseInside = false
    private var isBorderHighlighted = false

    func setShouldTrackMouse(_ track: Bool) {
        print("setShouldTrackMouse: track=\(track), current shouldTrackMouse=\(shouldTrackMouse), mouseMonitor=\(mouseMonitor != nil)")
        fflush(stdout)

        shouldTrackMouse = track

        if !track {
            // 不追踪时，移除监听
            if let monitor = mouseMonitor {
                NSEvent.removeMonitor(monitor)
                self.mouseMonitor = nil
            }
            updateBorderHighlight(active: false)
            protectedUntil = nil
            isMouseInside = false
        } else {
            // 需要追踪时，如果没有监听则添加
            if mouseMonitor == nil && isCardReady {
                print("setShouldTrackMouse: adding mouse monitor")
                fflush(stdout)
                setupMouseTracking()
                // 立即检查鼠标是否已在卡片内
                checkInitialMousePosition()
            }
        }
    }

    private func checkInitialMousePosition() {
        guard isCardReady, shouldTrackMouse else { return }

        let mouseLoc = NSEvent.mouseLocation
        let cardRectInScreen = convertToScreen(frame)
        let isInside = cardRectInScreen.contains(mouseLoc)

        print("checkInitialMousePosition: isInside=\(isInside), protectedUntil=\(protectedUntil)")
        fflush(stdout)

        if isInside {
            isMouseInside = true
            // 如果没有保护期，立即显示边框
            if protectedUntil == nil || Date() >= protectedUntil! {
                print("checkInitialMousePosition: mouse already inside, showing border")
                fflush(stdout)
                updateBorderHighlight(active: true)
            }
        }
    }

    func setProtectionDelay(_ delay: TimeInterval) {
        protectedUntil = Date().addingTimeInterval(delay)
        print("setProtectionDelay: delay=\(delay), protectedUntil=\(protectedUntil)")
        fflush(stdout)

        // 在保护期结束时检查鼠标位置
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.checkAfterProtectionEnd()
        }
    }

    private func checkAfterProtectionEnd() {
        guard isCardReady, shouldTrackMouse, isMouseInside else { return }
        guard protectedUntil == nil || Date() >= protectedUntil! else { return }

        print("checkAfterProtectionEnd: protection ended, mouse inside, showing border")
        fflush(stdout)
        updateBorderHighlight(active: true)
    }

    private func updateBorderHighlight(active: Bool) {
        print("updateBorderHighlight: active=\(active), isMouseInside=\(isMouseInside), isBorderHighlighted=\(isBorderHighlighted)")
        fflush(stdout)

        isBorderHighlighted = active
        // Ghostty white #C5C8C6
        if active {
            layer?.borderWidth = 1.5
            layer?.borderColor = NSColor(red: 0.773, green: 0.784, blue: 0.776, alpha: 0.35).cgColor
        } else {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor(red: 0.773, green: 0.784, blue: 0.776, alpha: 0.1).cgColor
        }
    }

    init(alertInfo: AlertInfo, maxWidth: CGFloat) {
        self.alertInfo = alertInfo
        let parsed = alertInfo.parsedMessage

        // 计算高度
        let hasResponse = parsed.response != nil && !parsed.response!.isEmpty
        let hasPrompt = parsed.prompt != nil && !parsed.prompt!.isEmpty
        let hasMeta = !parsed.metaLines.isEmpty

        // 计算 prompt 高度
        var promptHeight: CGFloat = 0
        if let prompt = parsed.prompt, hasPrompt {
            let maxWidth = maxWidth - Constants.cardPadding * 2 - 12
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            paragraphStyle.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(red: 0.773, green: 0.784, blue: 0.776, alpha: 0.7),  // Ghostty white
                .paragraphStyle: paragraphStyle
            ]
            let attrString = NSAttributedString(string: prompt, attributes: attrs)
            let rect = attrString.boundingRect(
                with: NSSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin]
            )
            promptHeight = ceil(rect.height)
        }
        self.promptHeight = promptHeight

        // 计算 meta 高度
        self.metaHeight = CGFloat(parsed.metaLines.count) * Constants.metaLineHeight

        // 计算响应高度（屏幕高度的 75%，但不小于 200）
        if let screen = NSScreen.main {
            self.maxResponseHeight = max(Constants.minResponseHeight, min(screen.frame.height * 0.75, Constants.maxResponseHeight))
        }

        // 计算总高度
        var cardHeight = Constants.cardPadding * 2 + Constants.titleHeight + Constants.innerSpacing
        if hasPrompt { cardHeight += promptHeight + Constants.innerSpacing }
        if hasResponse { cardHeight += maxResponseHeight + Constants.innerSpacing }
        if hasMeta { cardHeight += metaHeight + Constants.innerSpacing }
        cardHeight += Constants.hintHeight

        let frame = NSRect(x: 0, y: 0, width: maxWidth, height: cardHeight)
        super.init(frame: frame)

        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        wantsLayer = true
        alphaValue = 0
        layer?.transform = CATransform3DMakeScale(0.95, 0.95, 1)

        // 毛玻璃背景
        let bgView = NSVisualEffectView(frame: bounds)
        bgView.blendingMode = .behindWindow
        bgView.material = .dark
        bgView.state = .active
        bgView.wantsLayer = true
        bgView.layer?.cornerRadius = 16
        addSubview(bgView)

        // 深色遮罩层 — 压暗磨砂透光，保证文字在亮背景下的可读性
        // Ghostty black #1D1F21: 带蓝灰调的深色，比纯黑更柔和自然
        let darkOverlay = NSView(frame: bounds)
        darkOverlay.wantsLayer = true
        darkOverlay.layer?.backgroundColor = NSColor(red: 0.114, green: 0.122, blue: 0.129, alpha: 0.65).cgColor
        darkOverlay.layer?.cornerRadius = 16
        addSubview(darkOverlay)

        // 卡片样式
        layer?.backgroundColor = NSColor(red: 0.114, green: 0.122, blue: 0.129, alpha: 0.95).cgColor
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        // Ghostty white #C5C8C6
        layer?.borderColor = NSColor(red: 0.773, green: 0.784, blue: 0.776, alpha: 0.1).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.5).cgColor
        layer?.shadowOffset = CGSize(width: 0, height: 8)
        layer?.shadowRadius = 24
        layer?.shadowOpacity = 1

        let cardWidth = bounds.width
        var currentY = bounds.height - Constants.cardPadding - Constants.titleHeight

        // 标题
        let titleField = NSTextField(labelWithString: alertInfo.request.title)
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        // Ghostty white #C5C8C6
        titleField.textColor = NSColor(red: 0.773, green: 0.784, blue: 0.776, alpha: 0.55)
        titleField.alignment = NSTextAlignment.center
        titleField.sizeToFit()
        titleField.frame = NSRect(
            x: (cardWidth - titleField.frame.width) / 2,
            y: currentY,
            width: titleField.frame.width,
            height: Constants.titleHeight
        )
        addSubview(titleField)

        // Prompt（带左侧竖线）
        let parsed = alertInfo.parsedMessage
        if let prompt = parsed.prompt, promptHeight > 0 {
            currentY -= Constants.innerSpacing + promptHeight

            // 左侧竖线
            let accentLine = NSView(frame: NSRect(
                x: Constants.cardPadding,
                y: currentY,
                width: 3,
                height: promptHeight
            ))
            accentLine.wantsLayer = true
            // Ghostty blue #81A2BE
            accentLine.layer?.backgroundColor = NSColor(red: 0.506, green: 0.635, blue: 0.745, alpha: 0.7).cgColor
            accentLine.layer?.cornerRadius = 1.5
            addSubview(accentLine)

            // Prompt 文本
            let maxWidth = cardWidth - Constants.cardPadding * 2 - 12
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            paragraphStyle.lineBreakMode = .byWordWrapping
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 14, weight: .regular),
                .foregroundColor: NSColor(red: 0.773, green: 0.784, blue: 0.776, alpha: 0.7),  // Ghostty white
                .paragraphStyle: paragraphStyle
            ]
            let attrString = NSAttributedString(string: prompt, attributes: attrs)

            let promptField = NSTextField(frame: NSRect(
                x: Constants.cardPadding + 12,
                y: currentY,
                width: maxWidth,
                height: promptHeight
            ))
            promptField.isBezeled = false
            promptField.drawsBackground = false
            promptField.isEditable = false
            promptField.isSelectable = true
            promptField.attributedStringValue = attrString
            addSubview(promptField)
        }

        // AI 回复（WebView）
        if let response = parsed.response, !response.isEmpty {
            currentY -= Constants.innerSpacing + maxResponseHeight

            let webWidth = cardWidth - Constants.cardPadding * 2
            let webConfig = WKWebViewConfiguration()
            let webView = WKWebView(frame: NSRect(
                x: Constants.cardPadding,
                y: currentY,
                width: webWidth,
                height: maxResponseHeight
            ), configuration: webConfig)
            webView.setValue(false, forKey: "drawsBackground")
            webView.navigationDelegate = self

            let htmlContent = generateHTMLPage(markdown: response)
            webView.loadHTMLString(htmlContent, baseURL: nil)

            addSubview(webView)
            self.webView = webView
        }

        // 元信息
        if !parsed.metaLines.isEmpty {
            for (index, line) in parsed.metaLines.enumerated() {
                let lineY = currentY - Constants.innerSpacing - CGFloat(index) * Constants.metaLineHeight
                let lineField = NSTextField(labelWithString: line)
                lineField.font = NSFont.systemFont(ofSize: 12, weight: .medium)
                // Ghostty white #C5C8C6
                lineField.textColor = NSColor(red: 0.773, green: 0.784, blue: 0.776, alpha: 0.5)
                lineField.alignment = .left
                lineField.sizeToFit()
                lineField.frame = NSRect(
                    x: Constants.cardPadding,
                    y: lineY - Constants.metaLineHeight,
                    width: cardWidth - Constants.cardPadding * 2,
                    height: Constants.metaLineHeight
                )
                addSubview(lineField)
            }
            currentY -= Constants.innerSpacing + metaHeight
        }

        // 底部提示
        let hintField = NSTextField(labelWithString: "鼠标移出 或 右键点击 关闭")
        hintField.font = NSFont.systemFont(ofSize: 11, weight: .light)
        // Ghostty bright_black #666666
        hintField.textColor = NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 0.6)
        hintField.alignment = .center
        hintField.sizeToFit()
        hintField.frame = NSRect(
            x: (cardWidth - hintField.frame.width) / 2,
            y: Constants.cardPadding,
            width: hintField.frame.width,
            height: Constants.hintHeight
        )
        addSubview(hintField)

        // 如果没有 WebView，延迟显示
        if webView == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.animateIn()
            }
        }
    }

    // MARK: - WebView Delegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 如果是链接点击，在默认浏览器中打开
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.getElementById('content').scrollHeight") { [weak self] result, error in
            guard let self = self, let actualHeight = result as? CGFloat else { return }

            DispatchQueue.main.async {
                self.adjustWebViewHeight(actualHeight: actualHeight)
                self.animateIn()
            }
        }
    }

    private func adjustWebViewHeight(actualHeight: CGFloat) {
        guard let webView = webView else { return }

        let finalHeight = min(actualHeight + 10, maxResponseHeight)
        let heightDiff = finalHeight - webView.frame.height

        if abs(heightDiff) < 20 {
            if actualHeight > maxResponseHeight {
                webView.evaluateJavaScript("document.getElementById('content').style.overflowY = 'auto';", completionHandler: nil)
            }
            return
        }

        // 调整 WebView 高度
        var webFrame = webView.frame
        webFrame.size.height = finalHeight
        webView.frame = webFrame

        // 调整上方元素位置
        for subview in subviews {
            if subview === webView { continue }
            var frame = subview.frame
            if frame.origin.y >= webFrame.origin.y {
                frame.origin.y += heightDiff
            }
            subview.frame = frame
        }

        // 调整自身高度
        var cardFrame = frame
        cardFrame.size.height += heightDiff
        // 保持垂直居中：调整 y 坐标以补偿高度变化
        cardFrame.origin.y -= heightDiff / 2
        self.frame = cardFrame

        // 启用滚动
        if actualHeight > maxResponseHeight {
            webView.evaluateJavaScript("document.getElementById('content').style.overflowY = 'auto';", completionHandler: nil)
        }
    }

    // MARK: - 动画

    private func animateIn() {
        // 缩放动画
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 0.95
        scaleAnimation.toValue = 1.0
        scaleAnimation.duration = Constants.scaleAnimationDuration
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(scaleAnimation, forKey: "scaleIn")

        // 淡入
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.fadeInDuration
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            self?.isCardReady = true
            self?.playSound()
            // 如果需要追踪鼠标，启动鼠标追踪
            if self?.shouldTrackMouse == true {
                self?.setupMouseTracking()
            }
            self?.onReady?()
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1.0
        scaleAnimation.toValue = 0.95
        scaleAnimation.duration = Constants.fadeOutDuration
        scaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer?.add(scaleAnimation, forKey: "scaleOut")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Constants.fadeOutDuration
            animator().alphaValue = 0
        } completionHandler: {
            completion()
        }
    }

    private func playSound() {
        guard !hasPlayedSound else { return }
        hasPlayedSound = true

        guard let soundName = alertInfo.request.sound else { return }
        let lowercased = soundName.lowercased()

        if lowercased == "none" || lowercased == "silent" || lowercased == "off" {
            return
        } else if soundName.hasPrefix("/") || soundName.hasPrefix("~") {
            let expandedPath = (soundName as NSString).expandingTildeInPath
            if let fileSound = NSSound(contentsOfFile: expandedPath, byReference: false) {
                fileSound.play()
            }
        } else {
            NSSound(named: NSSound.Name(soundName))?.play()
        }
    }

    // MARK: - 鼠标追踪

    private func setupMouseTracking() {
        guard shouldTrackMouse else { return }
        guard window != nil else { return }

        print("setupMouseTracking called")
        fflush(stdout)

        // 不在这里初始化 isMouseInside
        // 让 handleMouseMoved 根据鼠标移动来判断进入/离开

        // 鼠标移动监听
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
        print("setupMouseTracking: monitor added")
        fflush(stdout)
    }

    private func handleMouseMoved() {
        guard isCardReady, shouldTrackMouse else { return }

        let mouseLoc = NSEvent.mouseLocation
        let cardRectInScreen = convertToScreen(frame)
        let isInside = cardRectInScreen.contains(mouseLoc)

        // 检查是否过了保护期
        let isProtected = protectedUntil != nil && Date() < protectedUntil!

        print("handleMouseMoved: isInside=\(isInside), isMouseInside=\(isMouseInside), isProtected=\(isProtected)")
        fflush(stdout)

        if isInside {
            // 鼠标进入
            if !isMouseInside {
                isMouseInside = true
                // 如果过了保护期，显示边框
                if !isProtected {
                    print("handleMouseMoved: mouse entered, showing border")
                    fflush(stdout)
                    updateBorderHighlight(active: true)
                }
            }
        } else {
            // 鼠标离开
            if isMouseInside {
                isMouseInside = false
                // 如果边框是亮的，关闭卡片
                if isBorderHighlighted {
                    closeCard()
                }
                updateBorderHighlight(active: false)
            }
        }
    }

    func handleRightClick() {
        closeCard()
    }

    func handleCopy() {
        guard let webView = webView else { return }
        webView.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            if let selectedText = result as? String, !selectedText.isEmpty {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(selectedText, forType: .string)
            }
        }
    }

    private func closeCard() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        onClose?()
    }

    func convertToScreen(_ rect: NSRect) -> NSRect {
        guard let window = window else { return rect }
        let windowFrame = window.frame
        return NSRect(
            x: windowFrame.origin.x + rect.origin.x,
            y: windowFrame.origin.y + rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    // MARK: - 布局更新

    func updatePosition(y: CGFloat) {
        var newFrame = frame
        newFrame.origin.y = y
        frame = newFrame
    }

    var cardHeight: CGFloat {
        return frame.height
    }

    // MARK: - 徽章

    func setPendingCount(_ count: Int) {
        // 移除旧徽章
        badgeView?.removeFromSuperview()
        badgeView = nil

        guard count > 0 else { return }

        // 创建徽章
        let badgeSize: CGFloat = 24
        let badge = NSView(frame: NSRect(
            x: bounds.width - Constants.cardPadding - badgeSize,
            y: bounds.height - Constants.cardPadding - badgeSize,
            width: badgeSize,
            height: badgeSize
        ))
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = badgeSize / 2

        // 数字文字
        let label = NSTextField(labelWithString: "\(count)")
        label.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        label.frame = NSRect(
            x: (badgeSize - label.frame.width) / 2,
            y: (badgeSize - label.frame.height) / 2,
            width: label.frame.width,
            height: label.frame.height
        )
        badge.addSubview(label)

        addSubview(badge)
        badgeView = badge
    }
}
