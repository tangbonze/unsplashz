#!/bin/bash
# 安装 UnsplashZ.spoon 到 ~/.hammerspoon/Spoons/
# 只复制文件，不改动你的 init.lua
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
SPOON_DIR="$HS_DIR/Spoons"

if [ ! -d "$HS_DIR" ]; then
  echo "找不到 $HS_DIR —— 先安装并运行一次 Hammerspoon。"
  exit 1
fi

mkdir -p "$SPOON_DIR"

if [ -d "$SPOON_DIR/UnsplashZ.spoon" ]; then
  BACKUP="$SPOON_DIR/UnsplashZ.spoon.bak.$(date +%Y%m%d%H%M%S)"
  mv "$SPOON_DIR/UnsplashZ.spoon" "$BACKUP"
  echo "已有旧版本，备份到 $(basename "$BACKUP")"
fi

cp -R "$REPO_DIR/UnsplashZ.spoon" "$SPOON_DIR/"
echo "已安装: $SPOON_DIR/UnsplashZ.spoon"

# 可选：安装图标渲染脚本
if [ -f "$REPO_DIR/icons/make_icon.swift" ]; then
  mkdir -p "$HS_DIR/icons"
  cp "$REPO_DIR/icons/make_icon.swift" "$REPO_DIR/icons/set_icon.sh" "$HS_DIR/icons/"
  chmod +x "$HS_DIR/icons/set_icon.sh"
  echo "已安装图标脚本: $HS_DIR/icons/set_icon.sh"
fi

echo
echo "最后一步：把下面的代码粘到 $HS_DIR/init.lua 末尾，然后重载配置。"
echo "------------------------------------------------------------"
cat "$REPO_DIR/examples/init.lua.snippet" | head -40
echo "------------------------------------------------------------"
echo "完整片段见 $REPO_DIR/examples/init.lua.snippet"
echo
echo "提示：首次使用需在「系统设置 → 隐私与安全性 → 辅助功能」里勾选 Hammerspoon，否则快捷键无效。"
