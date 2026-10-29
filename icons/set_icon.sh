#!/bin/bash
# 更换 UnsplashZ 菜单栏图标（macOS 原生 SF Symbol）
#
# 用法:
#   ~/.hammerspoon/icons/set_icon.sh photo.stack
#   ~/.hammerspoon/icons/set_icon.sh mountain.2.fill
#
# 可选符号见 ~/.hammerspoon/icons/symbols/_preview.png
# 重新生成图标并热重载 Hammerspoon，无需重启。

set -e
SYMBOL="${1:-photo.on.rectangle}"
DIR="$HOME/.hammerspoon/icons"
HS="/Applications/Hammerspoon.app/Contents/Frameworks/hs/hs"

cd "$DIR"
swift make_icon.swift "$SYMBOL" "$DIR/unsplashz.png"
"$HS" -c 'hs.reload()' >/dev/null 2>&1 || true
echo "菜单栏图标已切换为: $SYMBOL"
