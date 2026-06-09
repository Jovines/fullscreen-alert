---
name: fsalert-dev-test
description: >-
  fullscreen-alert 项目的开发自测工作流。当在该仓库（fullscreen-alert）内修改任何代码后，
  需要验证 UI/行为是否符合预期时使用：编译、安装、重启 daemon、发送测试通知、
  用内置 --dump 命令抓取窗口快照（PNG + 精确 frame）、肉眼或程序化校验布局。
  适用于所有 UI 改动、布局调整、新增交互、修 bug 后的回归验证等场景，
  不限于某次具体功能。触发词：fsalert 自测 / 验证 fullscreen-alert / 重启 daemon /
  dump 验证 / 抓取 alert 快照 / 在 fullscreen-alert 仓库内做改动验证。
argument-hint: 无（按下方步骤逐步执行）
user-invocable: true
allowed-tools: Bash, Read, Edit, Write, Grep, Glob
---

# fullscreen-alert 自测工作流（通用）

本 skill 是 `fullscreen-alert` 仓库的**通用开发自测脚手架**，
用于在任何代码改动后快速验证：编译 → 安装 → 重启 daemon → 触发场景 → 抓快照 → 校验。
**不需要任何额外系统权限**（屏幕录制/辅助功能均不需要）。

---

## 核心原理

`fullscreen-alert` 二进制提供了一条调试命令 `--dump <path>`：

- daemon 在内部用 `NSView.cacheDisplay(in:to:)` 把 containerView 渲染成 PNG
- 同步打印所有卡片在屏幕坐标系下的精确 frame
- 完全在自身进程内完成，**不调用 `screencapture`，不需要任何权限**

输出的 PNG 即可直接用 `Read` 工具看图；layout snapshot 文本可程序化校验位置。

---

## 标准自测流程

> **重要**：每一步都要分多次 Bash 调用，**不要把多步链成一行**。
> 历史教训：长链 `cmd1 && sleep && cmd2 && sleep && cmd3` 容易卡住，
> 因为客户端连接旧 daemon 与替换二进制的时序竞争会导致整个 shell 阻塞。

### 步骤 1：编译

```bash
cd /Users/bytedance/Developer/fullscreen-alert && swift build -c release 2>&1 | tail -5
```

期望最后一行：`Build complete!`。如有 error 先修代码再继续。

### 步骤 2：杀掉旧 daemon、清理状态

```bash
pkill -f "fullscreen-alert --daemon" 2>/dev/null
sleep 0.5
rm -f /tmp/fullscreen-alert.pid /tmp/fullscreen-alert.sock
echo cleaned
```

### 步骤 3：安装新二进制

```bash
cp /Users/bytedance/Developer/fullscreen-alert/.build/release/fullscreen-alert /usr/local/bin/fullscreen-alert
codesign --force --sign - /usr/local/bin/fullscreen-alert 2>&1 | tail -1
```

### 步骤 4：启动新 daemon（必须 `run_in_background: true`）

用 `Bash` 工具启动：
```bash
/usr/local/bin/fullscreen-alert --daemon
```
**关键**：调用 `Bash` 时一定要传 `run_in_background: true`，否则当前会话会被 daemon 占住直到超时。

随后等一下让 socket 就绪：
```bash
sleep 0.8 && cat /tmp/fullscreen-alert.pid && ls -la /tmp/fullscreen-alert.sock
```

### 步骤 5：发送测试通知（每条单独一次 Bash 调用）

> 不要把多条 `fullscreen-alert ...` 链在一起。每条单独调用，最稳。

Compact 模式（默认）：
```bash
/usr/local/bin/fullscreen-alert "构建完成" "Build #1234 succeeded in 2m 30s"
```
```bash
/usr/local/bin/fullscreen-alert "测试通过" "All 152 tests passed, coverage 87%"
```
```bash
/usr/local/bin/fullscreen-alert "部署完成" "Production deployment finished"
```

Full 模式：
```bash
/usr/local/bin/fullscreen-alert "重要任务" "强提醒|||## Markdown\n- a\n- b" --level full
```

### 步骤 6：dump 当前 UI 快照

```bash
sleep 0.8 && /usr/local/bin/fullscreen-alert --dump /tmp/fsalert-snap.png
```

返回内容包含：
- `Dumped to /tmp/fsalert-snap.png`
- `== Layout snapshot ==` + 每张卡片的 `frame=(x, y, w, h)`
- `window.frame`、`screen.frame`、`visibleFrame`、`ignoresMouseEvents`

### 步骤 7：用 Read 工具查看截图

```
Read /tmp/fsalert-snap.png
```

直接以图像形式展示，可以肉眼校验。

### 步骤 8：清理

```bash
/usr/local/bin/fullscreen-alert --close-all
```

如需停掉 daemon（一般不用，12h 自动空闲退出）：
```bash
pkill -f "fullscreen-alert --daemon"
```

---

## 程序化校验布局是否对

dump 返回的 layout snapshot 可以用脚本严格校验，比肉眼更可靠。

期望规则（compact 模式）：

- **顶部留白**：`card.y + card.height == visibleFrame.maxY - compactTopMargin`（默认 24）
- **横向居中**：所有 compact 卡片的整体左右边到屏幕中线距离相等
- **窗口默认穿透**：`window.ignoresMouseEvents == true`（compact 场景）
- **有 full 卡时**：`ignoresMouseEvents == false`，窗口背景为半透黑

举例（屏幕 1728 宽，3 张 compact 各 280 宽，间距 16）：
- totalWidth = 280×3 + 16×2 = 872
- 起始 X = 1728/2 - 872/2 = 428
- 卡片 X 序列：428, 724, 1020 ✓

---

## 常见坑 & 排查

### 1. 旧 daemon 残留导致命令打到老逻辑

症状：发通知没反应、`--dump` 报老格式、行为跟代码改动对不上。

修复：执行步骤 2 强制清理。客户端的版本检测虽然会自动重启，但偶尔时序不稳定，
手动清理最可靠。

### 2. 启动 daemon 时整个 bash 会话卡住

原因：忘了 `run_in_background: true`，前台模式 daemon 会持续运行直到 Bash 工具超时。

修复：`KillShell` 终止那个 Bash 会话，然后用 `run_in_background: true` 重新启动。

### 3. dump 返回 "Dump failed"

可能原因：
- 没有 alert 在显示，containerView bounds 为空 → 先发一条通知再 dump
- daemon 启动后还没 ensureWindow → 先发一条通知触发 window 创建

### 4. Trace/BPT trap: 5（Swift 主线程死锁）

原因：在主线程调用 `DispatchQueue.main.sync` 自己等自己。

修复：检查代码里所有 `DispatchQueue.main.sync` 是否套了 `Thread.isMainThread` 判断。
参考 `Sources/Daemon.swift` 里 `case .dump` 的写法。

### 5. screencapture 报 "could not create image from display"

那是命令行截图工具，**不要用它**。本 skill 用的是 `--dump`，完全不依赖 screencapture。

---

## 调试期间常用命令速查

| 命令 | 作用 |
|---|---|
| `fullscreen-alert <title> <msg>` | 发 compact 通知 |
| `fullscreen-alert <title> <msg> --level full` | 发 full 通知 |
| `fullscreen-alert --list` | 列出所有 alert id |
| `fullscreen-alert --close <id>` | 按 id 关闭单条 |
| `fullscreen-alert --close-all` | 关闭全部 |
| `fullscreen-alert --dump <path>` | 把当前窗口快照存为 PNG，并打印精确 frame + 每张卡的 hover/highlight 状态 |
| `fullscreen-alert --upgrade <id>` | 把指定 compact 升级为 full（绕过 mouseDown） |
| `fullscreen-alert --simulate-hover <x> <y>` | 模拟鼠标移到屏幕坐标 (x,y)，驱动所有 compact 卡的 hover 检测；移到非卡区会触发 hover-out 关闭 |
| `fullscreen-alert --simulate-rightclick <x> <y>` | 模拟在 (x,y) 右键 — 命中 compact 关该卡，否则关 full 顶层 |
| `fullscreen-alert disable` / `enable` | 临时禁用/启用 |

> **测试鼠标交互的标准路径**：
> 1. `--list` 拿 id；
> 2. `--simulate-hover <x> <y>` 移入卡片中心 → `--dump` 看 `isMouseInside / isBorderHighlighted` 状态；
> 3. `--simulate-hover 0 0` 移开 → `sleep 0.5` 等关闭动画 → `--list` 验证已关；
> 4. `--upgrade <id>` 等价于左键点击；
> 5. `--simulate-rightclick <x> <y>` 等价于右键。

---

## 调试期间长期带 daemon log

需要观察 daemon 内部 print 时，启动改成：
```bash
/usr/local/bin/fullscreen-alert --daemon > /tmp/fsalert-daemon.log 2>&1
```
（仍要 `run_in_background: true`）

之后随时 `cat /tmp/fsalert-daemon.log` 看输出。

---

## 修改了 Constants.version 后的特殊处理

代码里 bump version（如 1.2.0 → 1.3.0）是为了让客户端检测到版本不一致**自动 kill 旧 daemon**。
但调试期间为了确定，建议**手动**走步骤 2，不依赖自动机制。

---

## 改动后的最小验证集（按改动类型挑选）

每次改完后挑出与改动相关的场景跑一遍，对每个场景都 `--dump` 抓快照 + `Read` 看图，
同时核对 layout snapshot 数字是否符合预期。

### 通用场景库

| 类型 | 触发命令 | 关注点 |
|---|---|---|
| 单张 compact | `fullscreen-alert "T" "msg"` | 单卡居中、徽章渲染、内容截断 |
| 多张 compact | 连发 2~3 条 | 整组居中、间距、编号自增 |
| 关闭重排 | 关掉中间一张 | 剩余卡片重新居中、编号刷新 |
| 单张 full | `... --level full` | 黑幕、居中、Markdown、声音 |
| 多张 full | 连发 2~3 条 full | 顶层居中、底层左下偏移堆叠 |
| compact + full 混合 | 先 compact 再 full | 黑幕渐入、compact 不被遮罩吃掉 |
| 鼠标穿透 | 仅 compact 场景 | `ignoresMouseEvents=true`，鼠标在卡内时翻转为 false |
| 关闭交互 | hover-in-out / 右键 | 鼠标位置命中正确卡片 |

### 典型期望（compact 默认配置）

屏幕宽 W、卡片宽 280、间距 16、N 张：
- `totalWidth = 280·N + 16·(N-1)`
- `startX = W/2 - totalWidth/2`
- 卡片 X 序列：`startX, startX+296, startX+592, ...`
- `card.y + card.height == visibleFrame.maxY - compactTopMargin`（默认 24）

### 改动类型对应必跑场景

- **改了 compact 布局/尺寸**：单张 + 3 张 + 关掉中间
- **改了 full 渲染**：单张 full + Markdown 内容
- **改了鼠标交互**：手动验证（dump 抓不到鼠标状态，只能看 `ignoresMouseEvents`）
- **改了模式切换/升降级**：触发 compact，再用对应交互升级成 full，dump 前后两次
- **改了 socket/daemon**：`--list`/`--ping` 验证响应
- **改了配置加载**：先改 `~/.config/fullscreen-alert/config.json` 再发通知验证
