#!/bin/bash

# fullscreen-alert 安装脚本

set -e

echo "Installing fullscreen-alert..."

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 编译
echo "Building..."
cd "$SCRIPT_DIR"
swift build -c release

# 安装到 /usr/local/bin
echo "Installing to /usr/local/bin..."
cp .build/release/fullscreen-alert /usr/local/bin/
chmod +x /usr/local/bin/fullscreen-alert

# 创建 hook 脚本目录
mkdir -p ~/.claude/hooks

# 从仓库复制 hook 脚本
cp "$SCRIPT_DIR/stop-hook.sh" ~/.claude/hooks/stop-hook.sh
chmod +x ~/.claude/hooks/stop-hook.sh

# 更新 settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_PATH="$HOME/.claude/hooks/stop-hook.sh"

if [ -f "$SETTINGS_FILE" ]; then
    # 检查是否已有 Stop hook
    if ! grep -q '"Stop"' "$SETTINGS_FILE" 2>/dev/null; then
        # 添加 Stop hook 配置
        python3 << PYTHON_EOF
import json
import sys

try:
    with open('$SETTINGS_FILE', 'r') as f:
        settings = json.load(f)
except:
    settings = {}

if 'hooks' not in settings:
    settings['hooks'] = {}

settings['hooks']['Stop'] = [{
    'hooks': [{
        'type': 'command',
        'command': '$HOOK_PATH'
    }]
}]

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)
PYTHON_EOF
        echo "Hook configuration added to settings.json"
    else
        echo "Hook already configured in settings.json"
    fi
else
    echo "Creating settings.json..."
    cat > "$SETTINGS_FILE" << SETTINGS_EOF
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOOK_PATH"
          }
        ]
      }
    ]
  }
}
SETTINGS_EOF
fi

echo ""
echo "Installation complete!"
echo ""
echo "Usage:"
echo "  fullscreen-alert \"标题\" \"消息\" --sound Purr"
echo ""
echo "The Stop hook is now configured. When you stop a Claude conversation,"
echo "a notification will appear showing the conversation summary."
