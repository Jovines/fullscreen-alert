# fullscreen-alert

macOS 全屏提示工具，用于 CLI 工具完成时显示通知。

## 功能特性

- **守护进程模式** - 自动启动后台守护进程，支持多通知堆叠显示
- **用户无感** - 守护进程自动启动和退出，无需手动管理
- **全屏覆盖提示** - 半透明遮罩确保用户注意到
- **Markdown 渲染** - 使用 marked.js 渲染 AI 回复
- **自动高度调整** - 短内容自动缩小，长内容启用滚动
- **表格支持** - 每列最大宽度 450px，超出可横向滚动，行悬停高亮
- **多种关闭方式**：
  - 鼠标移出关闭
  - 右键点击关闭
- **自定义提示音** - 支持内置声音和自定义音频文件
- **动画效果** - 缩放 + 淡入组合动画，蒙层和卡片一起出现
- **内容复制** - 支持 Cmd+C 复制选中内容

## 安装

```bash
cd ~/Developer/fullscreen-alert
swift build -c release
cp .build/release/fullscreen-alert /usr/local/bin/
```

## 用法

```bash
fullscreen-alert <标题> [消息] [选项]
```

### 选项

| 选项 | 说明 |
|------|------|
| `--timeout <秒>` | 自动关闭超时时间 |
| `--sound <名称>` | 提示音（默认: Purr） |
| `--list` | 列出所有活跃通知 |
| `--close-all` | 关闭所有通知 |

### 提示音

- **内置声音**：`Glass`, `Blow`, `Bottle`, `Frog`, `Funk`, `Pop`, `Purr`, `Sosumi`, `Submarine`, `Tink`
- **静音**：`none`
- **自定义文件**：传入音频文件路径

### 示例

```bash
# 基本用法
fullscreen-alert "完成" "任务已完成"

# 静音
fullscreen-alert "完成" "任务已完成" --sound none

# 自定义声音
fullscreen-alert "完成" "任务已完成" --sound Pop

# 自定义音频文件
fullscreen-alert "完成" "任务已完成" --sound ~/alert.wav

# 列出所有通知
fullscreen-alert --list

# 关闭所有通知
fullscreen-alert --close-all
```

## 消息格式

消息使用 `|||` 作为分隔符区分不同部分：

```
用户问题|||AI 回复|||路径: /path/to/repo|||分支: main|||模型: claude-sonnet
```

### Claude Code 集成

在 `~/.claude/settings.json` 中配置 Stop Hook：

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/Users/<username>/.claude/hooks/stop-hook.sh"
          }
        ]
      }
    ]
  }
}
```

## 关闭方式

| 方式 | 说明 |
|------|------|
| 鼠标移出 | 鼠标初始在卡片内→移出关闭；或初始在外→进入后再移出关闭 |
| 右键点击 | 任意位置右键点击关闭 |

## 多通知支持

- 多个通知自动垂直堆叠显示
- 每个通知独立处理鼠标交互
- 关闭一个通知后，剩余通知自动重新布局
- 守护进程空闲 5 分钟后自动退出

## 文件结构

```
fullscreen-alert/
├── Sources/
│   ├── main.swift           # 客户端入口
│   ├── Daemon.swift         # 守护进程主逻辑
│   ├── AlertManager.swift   # 通知管理器
│   ├── AlertCardView.swift  # 单个通知卡片
│   ├── Models.swift         # 数据模型
│   ├── Constants.swift      # 常量定义
│   └── HTMLGenerator.swift  # HTML 生成
├── Package.swift            # Swift 包配置
└── README.md                # 说明文档
```

## 相关文件

| 文件 | 路径 |
|------|------|
| Hook 脚本 | `~/.claude/hooks/stop-hook.sh` |
| 配置文件 | `~/.claude/settings.json` |
| 可执行文件 | `/usr/local/bin/fullscreen-alert` |
| Socket 文件 | `/tmp/fullscreen-alert.sock` |
| PID 文件 | `/tmp/fullscreen-alert.pid` |

## 技术实现

- **UI 框架**：AppKit (macOS 原生)
- **守护进程通信**：Unix Domain Socket
- **Markdown 渲染**：WKWebView + marked.js
- **高度计算**：JavaScript `scrollHeight`
- **滚动支持**：CSS `overflow-y: auto`
- **动画**：CABasicAnimation + NSAnimationContext
- **毛玻璃效果**：NSVisualEffectView

## 自定义

### 修改配置

编辑 `Sources/Constants.swift`：

```swift
static let cardWidth: CGFloat = 930        // 卡片宽度
static let screenMargin: CGFloat = 50      // 屏幕边距
static let cardSpacing: CGFloat = 20       // 多卡片间距
static let maxTableColumnWidth: CGFloat = 450  // 表格列最大宽度
static let daemonIdleTimeout: TimeInterval = 300  // 守护进程空闲超时
```

修改后需要重新编译。

## 开发流程

修改代码后需要重新编译安装：

```bash
cd ~/Developer/fullscreen-alert
swift build -c release
cp .build/release/fullscreen-alert /usr/local/bin/
codesign --force --sign - /usr/local/bin/fullscreen-alert
```

如果修改了守护进程相关代码（Daemon.swift、AlertManager.swift、AlertCardView.swift 等），还需要重启守护进程：

```bash
pkill -f fullscreen-alert
rm -f /tmp/fullscreen-alert.pid /tmp/fullscreen-alert.sock
```

**一键命令**（编译 + 重启 + 安装 + 签名）：

```bash
cd ~/Developer/fullscreen-alert && swift build -c release && pkill -f fullscreen-alert; rm -f /tmp/fullscreen-alert.pid /tmp/fullscreen-alert.sock; cp .build/release/fullscreen-alert /usr/local/bin/ && codesign --force --sign - /usr/local/bin/fullscreen-alert
```

如果只修改了客户端逻辑（main.swift 里非守护进程部分），编译安装即可，无需重启守护进程。

## 故障排查

### 提示不显示

1. 检查 `/usr/local/bin/fullscreen-alert` 是否存在
2. 检查 hook 脚本是否有执行权限：`chmod +x ~/.claude/hooks/stop-hook.sh`
3. 查看调试文件：`/tmp/claude-hook-debug.json`
4. 检查守护进程状态：`fullscreen-alert --list`

### 守护进程问题

```bash
# 手动清理
rm /tmp/fullscreen-alert.sock /tmp/fullscreen-alert.pid
```

### 编译错误

1. 确认 Swift 版本：`swift --version`
2. 检查 Xcode 命令行工具是否安装：`xcode-select --install`

## License

MIT
