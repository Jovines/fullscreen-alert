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

# 创建 hook 脚本
cat > ~/.claude/hooks/stop-hook.sh << 'HOOK_EOF'
#!/bin/bash

INPUT=$(cat)
echo "$INPUT" > /tmp/claude-hook-debug.json

# 获取工作目录
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
DIR_NAME=$(basename "$CWD" 2>/dev/null)

# 获取 transcript 路径
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path' 2>/dev/null)

# 获取用户最后的 prompt
LAST_PROMPT=$(grep '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -30 | while IFS= read -r line; do
    CONTENT_TYPE=$(echo "$line" | jq -r '.message.content | type' 2>/dev/null)
    if [ "$CONTENT_TYPE" = "string" ]; then
        CONTENT=$(echo "$line" | jq -r '.message.content' 2>/dev/null)
        if [ -n "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
            echo "$CONTENT"
        fi
    fi
done | tail -1)

# 获取 AI 最后的回复
AI_RESPONSE=$(jq -r '.last_assistant_message // ""' /tmp/claude-hook-debug.json 2>/dev/null)

# 获取 git 分支
GIT_BRANCH=$(grep '"gitBranch"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | jq -r '.gitBranch' 2>/dev/null)

# 获取模型名称
MODEL_NAME=$(grep '"type":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | jq -r '.message.model // empty' 2>/dev/null)

# 截取 prompt 前 50 字符
if [ -n "$LAST_PROMPT" ]; then
    PROMPT_SUMMARY="${LAST_PROMPT:0:50}"
    if [ ${#LAST_PROMPT} -gt 50 ]; then
        PROMPT_SUMMARY="${PROMPT_SUMMARY}..."
    fi
else
    PROMPT_SUMMARY="目录: $DIR_NAME"
fi

# 构建消息
MESSAGE="${PROMPT_SUMMARY}"
if [ -n "$AI_RESPONSE" ]; then
    MESSAGE="${MESSAGE}|||${AI_RESPONSE}"
fi
if [ -n "$CWD" ]; then
    MESSAGE="${MESSAGE}|||路径: ${CWD}"
fi
if [ -n "$GIT_BRANCH" ]; then
    MESSAGE="${MESSAGE}|||分支: ${GIT_BRANCH}"
fi
if [ -n "$MODEL_NAME" ]; then
    MESSAGE="${MESSAGE}|||模型: ${MODEL_NAME}"
fi

# 发送通知
nohup fullscreen-alert "Claude 响应完成" "$MESSAGE" --sound Purr > /dev/null 2>&1 &
disown
HOOK_EOF

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
