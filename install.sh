#!/usr/bin/env bash
# mouseAI v0 (看懂) 安装脚本
# 用法:curl -fsSL https://raw.githubusercontent.com/luanrj-ai/mouse-ai/main/install.sh | bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/luanrj-ai/mouse-ai/main"
HS_DIR="$HOME/.hammerspoon"
DEST_DIR="$HS_DIR/mouse-ai"
DEST="$DEST_DIR/kandong.lua"
INIT="$HS_DIR/init.lua"
MARKER="mouse-ai/kandong.lua"

echo "→ 安装 mouseAI v0(看懂)…"

# 1) 前置检查(缺了只提醒,不中断)
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  echo "⚠️  没找到 Claude Code(claude)。请先安装并登录:https://claude.com/claude-code"
fi
if [ ! -d "/Applications/Hammerspoon.app" ]; then
  echo "⚠️  没装 Hammerspoon。请先装:brew install --cask hammerspoon"
fi

# 2) 下载 kandong.lua
mkdir -p "$DEST_DIR"
echo "→ 下载 kandong.lua"
curl -fsSL "$REPO_RAW/v0-kandong/kandong.lua" -o "$DEST"

# 3) 接进 Hammerspoon 的 init.lua(幂等:已接过就不重复)
mkdir -p "$HS_DIR"
touch "$INIT"
if grep -qF "$MARKER" "$INIT"; then
  echo "→ init.lua 已经接好,跳过"
else
  {
    echo ""
    echo "-- mouseAI v0(看懂)— 划选看不懂的内容,按 ⌥? 解释"
    echo 'dofile(os.getenv("HOME") .. "/.hammerspoon/mouse-ai/kandong.lua")'
  } >> "$INIT"
  echo "→ 已写入 $INIT"
fi

# 4) 重载 Hammerspoon(若在运行;失败不影响,下面有手动办法)
if pgrep -x Hammerspoon >/dev/null 2>&1; then
  osascript -e 'tell application "Hammerspoon" to reload config' >/dev/null 2>&1 \
    || open -g "hammerspoon://reload" >/dev/null 2>&1 || true
  echo "→ 已尝试重载 Hammerspoon"
fi

cat <<'DONE'

✅ 装好了。还差两步:
   1) 打开 Hammerspoon —— 系统会弹一次「辅助功能」授权,点同意
      (用来读你在终端里选中的文字;不截图、不上传)
      如果快捷键没反应:点菜单栏 Hammerspoon 图标 → Reload Config
   2) 打开终端、运行 claude,划选任意看不懂的一段,按 ⌥?

   三个键:⌥? 解释/看屏 · ⌘⌥? 详细 · ⌘? 卡点小结
DONE
