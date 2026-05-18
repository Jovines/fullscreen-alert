#!/bin/bash

INPUT=$(cat)
echo "$INPUT" > /tmp/claude-hook-debug.json

# 获取工作目录
CWD=$(echo "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
DIR_NAME=$(basename "$CWD" 2>/dev/null)

# 获取 transcript 路径
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path' 2>/dev/null)

# 获取用户最后的 prompt（从 message.content 字段提取）
LAST_PROMPT=$(grep '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -30 | while IFS= read -r line; do
    # 检查 message.content 是否是字符串类型
    CONTENT_TYPE=$(echo "$line" | jq -r '.message.content | type' 2>/dev/null)
    if [ "$CONTENT_TYPE" = "string" ]; then
        CONTENT=$(echo "$line" | jq -r '.message.content' 2>/dev/null)
        if [ -n "$CONTENT" ] && [ "$CONTENT" != "null" ]; then
            echo "$CONTENT"
        fi
    fi
done | tail -1)

# 获取 AI 最后的回复（用 jq 从文件读取）
AI_RESPONSE=$(jq -r '.last_assistant_message // ""' /tmp/claude-hook-debug.json 2>/dev/null)

# 获取 git 分支
GIT_BRANCH=$(grep '"gitBranch"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | jq -r '.gitBranch' 2>/dev/null)

# 获取模型名称
MODEL_NAME=$(grep '"type":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -1 | jq -r '.message.model // empty' 2>/dev/null)

# 计算耗时
FIRST_TIME=$(head -1 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.timestamp' 2>/dev/null)
LAST_TIME=$(tail -1 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '.timestamp' 2>/dev/null)
if [ -n "$FIRST_TIME" ] && [ -n "$LAST_TIME" ]; then
    START_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${FIRST_TIME:0:19}" +%s 2>/dev/null)
    END_SEC=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${LAST_TIME:0:19}" +%s 2>/dev/null)
    if [ -n "$START_SEC" ] && [ -n "$END_SEC" ]; then
        DURATION=$((END_SEC - START_SEC))
        if [ $DURATION -gt 0 ]; then
            DURATION_TEXT=" | ${DURATION}s"
        fi
    fi
fi

# 截取 prompt 前 50 字符
if [ -n "$LAST_PROMPT" ]; then
    PROMPT_SUMMARY="${LAST_PROMPT:0:50}"
    if [ ${#LAST_PROMPT} -gt 50 ]; then
        PROMPT_SUMMARY="${PROMPT_SUMMARY}..."
    fi
else
    PROMPT_SUMMARY="目录: $DIR_NAME"
fi

# AI 回复不限制字符数，完整显示
if [ -n "$AI_RESPONSE" ]; then
    AI_SUMMARY="$AI_RESPONSE"
fi

# 构建消息：使用特殊分隔符 ||| 来区分不同部分
MESSAGE="${PROMPT_SUMMARY}"
if [ -n "$AI_SUMMARY" ]; then
    MESSAGE="${MESSAGE}|||${AI_SUMMARY}"
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

# 调试：记录传递给 fullscreen-alert 的消息
echo "=== MESSAGE DEBUG ===" > /tmp/alert-message-debug.txt
echo "$MESSAGE" >> /tmp/alert-message-debug.txt
echo "=== END ===" >> /tmp/alert-message-debug.txt

# 完全异步执行，不阻塞
nohup fullscreen-alert "Claude 响应完成" "$MESSAGE" --sound Purr > /dev/null 2>&1 &
disown
