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

# 收尾要提醒的事,边装边往里塞,最后统一打印(用户不用边看边记)
TODO=()

echo "→ 安装 mouseAI v0(看懂)…"

# 仅支持 macOS
if [ "$(uname)" != "Darwin" ]; then
  echo "✋ 看懂 v0 目前只支持 macOS。Windows / Linux 还在路上。"
  exit 1
fi

# ---- 1) 前置:Claude Code(看懂复用它来解释,这是硬依赖)----
if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
  echo "→ 找到 Claude Code ✓"
else
  echo "⚠️  没找到 Claude Code。看懂是“复用”它来解释的,没有它装上也用不了。"
  TODO+=("装并登录 Claude Code:https://claude.com/claude-code (装好后重启终端)")
fi

# ---- 2) 前置:Hammerspoon(快捷键引擎)。没有就尽量帮你装 ----
if [ -d "/Applications/Hammerspoon.app" ]; then
  echo "→ 找到 Hammerspoon ✓"
elif command -v brew >/dev/null 2>&1; then
  echo "→ 没装 Hammerspoon,正在用 Homebrew 帮你装(可能要一两分钟)…"
  if brew install --cask hammerspoon; then
    echo "→ Hammerspoon 装好了 ✓"
  else
    echo "⚠️  自动安装没成功。"
    TODO+=("手动装 Hammerspoon:终端跑 brew install --cask hammerspoon,或去 https://www.hammerspoon.org 下载拖进“应用程序”")
  fi
else
  echo "⚠️  没装 Hammerspoon,也没找到 Homebrew,没法自动帮你装。"
  TODO+=("装 Hammerspoon:去 https://www.hammerspoon.org 下载,拖进“应用程序”即可(免费)")
fi

# ---- 3) 下载 kandong.lua ----
mkdir -p "$DEST_DIR"
echo "→ 下载 kandong.lua"
if ! curl -fsSL "$REPO_RAW/v0-kandong/kandong.lua" -o "$DEST"; then
  echo "❌ 下载失败。多半是网络问题(GitHub 连不上)。检查网络、或挂个代理后,重新跑一遍这条命令即可。"
  exit 1
fi

# ---- 4) 接进 Hammerspoon 的 init.lua(幂等:已接过就不重复)----
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

# ---- 5) 重载 Hammerspoon(若在运行)----
if pgrep -x Hammerspoon >/dev/null 2>&1; then
  osascript -e 'tell application "Hammerspoon" to reload config' >/dev/null 2>&1 \
    || open -g "hammerspoon://reload" >/dev/null 2>&1 || true
  echo "→ 已尝试重载 Hammerspoon"
fi

# ---- 6) 收尾:先把“还差什么”说清楚,再说怎么用 ----
echo ""
if [ ${#TODO[@]} -gt 0 ]; then
  echo "⚠️  文件装好了,但还差这些才能真正用起来:"
  for i in "${!TODO[@]}"; do
    echo "   $((i+1)). ${TODO[$i]}"
  done
  echo "   ↑ 补齐后,重新跑一遍本命令(或点菜单栏锤子图标 → Reload Config)。"
  echo ""
fi

cat <<'DONE'
✅ 看懂已就位。第一次还要做一件事(只做一次):
   • 打开 Hammerspoon —— 系统会弹一次「辅助功能」授权,点同意
     (用来读你在终端里选中的文字;读的是文字、不截图、不上传)
     没弹或快捷键没反应:系统设置 → 隐私与安全性 → 辅助功能 → 打开 Hammerspoon,
     再点菜单栏锤子图标 → Reload Config

怎么用:打开终端、运行 claude,划选任意看不懂的一段,按 ⌥?
   三个键:⌥? 解释/看屏 · ⌘⌥? 详细 · ⌘? 卡点小结
DONE
