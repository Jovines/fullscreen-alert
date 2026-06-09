import Cocoa
import WebKit

/// WebView 池：共享 WKProcessPool 让所有 full 卡复用同一个 web content 进程
/// daemon 启动时预热一次，避免首条 full 卡冷启动 ~1.5s
final class WebViewPool {
    static let shared = WebViewPool()

    /// 所有 WebView 共享的进程池 — 关键：让 JS 引擎/编译缓存复用
    let processPool = WKProcessPool()

    /// 共享 configuration
    let configuration: WKWebViewConfiguration

    /// 隐藏的预热 WebView（一直保留，强制 JS 引擎驻留内存）
    private var prewarmWebView: WKWebView?
    private var prewarmDone = false

    private init() {
        let config = WKWebViewConfiguration()
        config.processPool = processPool
        // 允许文件 URL 加载，避免一些边界情况
        if #available(macOS 10.13, *) {
            config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }
        self.configuration = config
    }

    /// 创建一个 WebView，使用共享 process pool（继承已编译的 JS 缓存）
    func makeWebView(frame: NSRect) -> WKWebView {
        return WKWebView(frame: frame, configuration: configuration)
    }

    /// daemon 启动后立即预热：创建一个 hidden WebView 加载完整 HTML 模板
    /// 这一步会触发 WKWebView 进程冷启动 + marked.js / highlight.js 编译
    /// 完成后即使该 WebView 销毁，process pool 内的 JIT 缓存仍保留
    func prewarm() {
        guard !prewarmDone else { return }
        prewarmDone = true

        // 必须在主线程调用
        DispatchQueue.main.async {
            let wv = WKWebView(frame: NSRect(x: -10000, y: -10000, width: 1, height: 1), configuration: self.configuration)
            wv.loadHTMLString(generateHTMLPage(markdown: "**warmup**"), baseURL: nil)
            self.prewarmWebView = wv
        }
    }
}
