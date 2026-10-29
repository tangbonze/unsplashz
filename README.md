# UnsplashZ.spoon

**中文** · [English](README.en.md)

给 [Hammerspoon](https://www.hammerspoon.org/) 用的随机风景壁纸插件：按屏幕物理像素取图、图源可自由配置、自动清理缓存。

> 改造自 [Hammerspoon/Spoons](https://github.com/Hammerspoon/Spoons) 的 UnsplashZ（作者 ashfinal，MIT）。
> 上游依赖的 `source.unsplash.com` 已于 2024 年中由 Unsplash 官方下线（现返回 HTTP 503），原版无法取图，因此重写了取图链路。

## 相比原版的改动

| 能力 | 原版 | 本版 |
|---|---|---|
| 取图 | `source.unsplash.com`（已下线） | **声明式图源链**，JSON 配置，失败自动降级 |
| 图源 | 仅 Unsplash | Unsplash API / picsum / Bing，也可自己加任意接口 |
| 尺寸 | 固定尺寸 | **自动跟随屏幕物理像素**（`currentMode()` 换算出真实像素，Retina 不再发虚） |
| 多屏 | 不支持 | 按宽高比分组，同比例共用一张图 |
| 缓存 | 只增不减 | 按天数自动清理，保留策略可配 |
| 菜单栏 | 文字 | **SF Symbols 模板图**，深浅色自动反色 |

## 安装

```bash
git clone https://github.com/tangbonze/unsplashz.git
cd unsplashz
./install.sh
```

脚本做的事只有两件：把 `UnsplashZ.spoon` 拷进 `~/.hammerspoon/Spoons/`，把 `examples/init.lua.snippet` 里的集成代码提示你粘进 `~/.hammerspoon/init.lua`（**不会**自动改写你的配置文件）。

手动装也行：

```bash
cp -R UnsplashZ.spoon ~/.hammerspoon/Spoons/
```

然后在 `~/.hammerspoon/init.lua` 末尾加：

```lua
function reloadUnsplashZ()
  local spoon = require("UnsplashZ")
  if spoon then
    local real = (spoon.getObj and spoon.getObj()) or spoon
    if not real.__inited then
      real.__inited = true
      real:init()
    end
    spoon = real
  end
  hs.hotkey.bind({"ctrl", "alt"}, "W", function()
    spoon:next({notify = true})
  end)
end
reloadUnsplashZ()
```

重载配置后菜单栏会出现图标，右下角菜单里可以直接换图、切分辨率、管图源。

## 用法

| 入口 | 说明 |
|---|---|
| `⌃⌥W` | 立即换一张（可在 `init.lua` 里改） |
| 菜单栏图标 | 左键弹出菜单：换图 / 分辨率 / 壁纸清理 / 图源设置 |
| 定时 | 默认每 3 小时自动换一张 |

## 分辨率怎么匹配

自动模式下读取 `hs.screen:currentMode()`，用 `width × scale` 得到**物理像素**（不是逻辑点）。例如 3440×1440 的 5K 屏显示为 `2365×990 @2x`，实际画布是 `4730×1980` —— 壁纸会按这个尺寸去取，一个像素都不浪费，也不会被系统拉伸变糊。

也可以在菜单里手动指定 12 种常见分辨率（1920×1080 到 5120×2880）。选了之后如果和屏幕比例差距超过 2%，日志会提示可能出现黑边或裁切。

多屏时按宽高比分组：比例相同的屏幕共用一张图（不重复下载），比例不同的各取一张。

## 图源怎么配

配置文件 `~/.hammerspoon/unsplashz_sources.json` 首次运行自动生成，改完在菜单点「重新加载图源配置」即可，不用重启。

最小例子（直接返回图片的接口）：

```json
{
  "sources": [
    {
      "name": "Picsum",
      "type": "direct",
      "url": "https://picsum.photos/seed/{seed}/{w}/{h}"
    }
  ]
}
```

需要先取 JSON 再拿图片地址的接口：

```json
{
  "name": "Bing",
  "type": "json",
  "url": "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8",
  "jsonPath": "images[].urlbase",
  "urlPrefix": "https://www.bing.com",
  "urlSuffix": "_UHD.jpg"
}
```

`jsonPath` 里的 `[]` 表示数组随机取一个。完整字段表、占位符、排查表见 **[docs/sources.md](docs/sources.md)**。

## API Key 放哪

**不要写进 JSON**。用占位符 `{key:名称}`，程序按顺序查找：

1. `~/.hammerspoon/secrets/名称.key`（文件里只放一行值，不要引号）
2. 环境变量 `名称_ACCESS_KEY`
3. 环境变量 `名称`（自动转大写）

取不到就跳过该图源，不会报错中断。

## 菜单栏图标

默认是 `photo.stack`（用 Swift 把 SF Symbol 渲染成 18pt@2x 模板 PNG）。换图标：

```bash
~/.hammerspoon/icons/set_icon.sh mountain.2.fill
```

`setIcon(image, true)` 的第二个参数是 template 标志——**这是图标能随菜单栏深浅色自动反色的关键**，单靠 `setIcon(img)` 不行。脚本会顺带热重载，不用重启 Hammerspoon。

## 已知限制

- **快捷键需要辅助功能权限**，首次安装到「系统设置 → 隐私与安全性 → 辅助功能」里勾上 Hammerspoon。
- macOS 27 上 `hs.eventtap.keyStroke` / AppleScript 合成的按键**送不到 Hammerspoon**，无法用脚本验证热键是否生效，只能人工实按。
- 本版 `hs.fs` 是 lfs 语义（`attributes().modification` 而非 `modificationDate`），且没有 `hs.image.imageFromSymbol`，所以图标走 Swift 渲染。
- Bing 图源最高 3840×2160，喂给 5K 屏会略微偏软（脚本会本地居中裁切到正确比例）。

## License

MIT，见 [LICENSE](LICENSE)。原始版权归 ashfinal。
