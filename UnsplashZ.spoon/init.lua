--- === UnsplashZ ===
---
--- 随机风景壁纸（自动换图）
---
--- 原始作者: ashfinal <ashfinal@gmail.com> · MIT License
--- 本地改造说明:
---   上游 source.unsplash.com 已于 2024 年中由 Unsplash 官方下线（现返回 HTTP 503），
---   原版无法取图。此处改为「用户可自定义的图源链」：
---     图源全部写在 ~/.hammerspoon/unsplashz_sources.json（首次运行自动生成），
---     按数组顺序依次尝试，第一个成功的生效，失败自动降级到下一个。
---     内置默认三档：Unsplash 官方 API（需 Access Key）/ picsum / Bing 每日壁纸。
---   完整设置规则见 ~/.hammerspoon/unsplashz_sources.md（菜单里可直接打开）。
---
--- 用法:
---   hs.loadSpoon("UnsplashZ")
---   UnsplashZ:init()      启动定时器（首次 5 秒后生效）
---   UnsplashZ:next()      立即换一张
---   UnsplashZ:stop()      停止定时器
---   UnsplashZ:reloadSources()   重新读取图源配置
---   UnsplashZ:testSources()     测试各图源连通性

local obj = {}
obj.__index = obj

obj.name = "UnsplashZ"
obj.version = "1.1-local"
obj.author = "ashfinal <ashfinal@gmail.com>"
obj.homepage = "https://github.com/Hammerspoon/Spoons"
obj.license = "MIT - https://opensource.org/licenses/MIT"

-- ==========================================================================
-- 配置
-- ==========================================================================
obj.interval = 3 * 60 * 60   -- 换图间隔（秒），默认 3 小时
obj.autoFit  = true          -- 自动按屏幕物理像素匹配壁纸（推荐）
obj.width    = 3840          -- 手动模式下的壁纸宽（autoFit = false 时生效）
obj.height   = 1600          -- 手动模式下的壁纸高
obj.keyword  = "nature"      -- Unsplash 官方 API 检索关键词
obj.dir      = os.getenv("HOME") .. "/.hammerspoon/wallpapers"

-- 分辨率选择：auto = 跟随当前屏幕；manual = 用下面指定的固定尺寸
obj.sizeMode      = "auto"
obj.manualWidth   = 3840
obj.manualHeight  = 1600

-- 壁纸缓存清理：保留 N 天，每 M 小时执行一次
obj.autoCleanup      = true
obj.retentionDays    = 7
obj.cleanupEveryHours = 24

-- 被禁用的图源名（菜单里点击切换；不修改用户的 unsplashz_sources.json）
obj.disabledSources  = {}

-- 常见分辨率（宽度 ≥ 1920），供用户在菜单里手动挑选
obj.commonResolutions = {
  {1920, 1080, "1920×1080  (16:9)"},
  {1920, 1200, "1920×1200  (16:10)"},
  {2560, 1440, "2560×1440  (16:9)"},
  {2560, 1600, "2560×1600  (16:10)"},
  {2688, 1512, "2688×1512  (16:10)"},
  {2880, 1800, "2880×1800  (16:10)"},
  {3024, 1964, "3024×1964  (16:10 Retina)"},
  {3440, 1440, "3440×1440  (21:9 超宽)"},
  {3840, 1600, "3840×1600  (21:9 超宽)"},
  {3840, 2160, "3840×2160  (4K 16:9)"},
  {5120, 2160, "5120×2160  (21:9 5K2K)"},
  {5120, 2880, "5120×2880  (5K 16:9)"},
}

local LOGFILE  = os.getenv("HOME") .. "/.hammerspoon/unsplashz.log"
local PREFSFILE = os.getenv("HOME") .. "/.hammerspoon/unsplashz_prefs.json"
-- 图源配置文件（用户自行编辑，首次运行自动生成）+ 规则说明文档
local SOURCESFILE = os.getenv("HOME") .. "/.hammerspoon/unsplashz_sources.json"
local RULESFILE   = os.getenv("HOME") .. "/.hammerspoon/unsplashz_sources.md"

-- 前向声明（buildTargets 定义在文件后部，但 sizeDescription 会提前引用它）
local buildTargets

local UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " ..
           "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

-- ==========================================================================
-- 日志：Hammerspoon 控制台 + 文件
-- ==========================================================================
local function log(msg)
  msg = tostring(msg)
  local fh = io.open(LOGFILE, "a")
  if fh then
    fh:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), msg))
    fh:close()
  end
  pcall(function() hs.logger.new("UnsplashZ", "info").i(msg) end)
end

-- 清理间隔的显示文本：天数一律取整，绝不出现 0.25 / 1.5 这类小数
-- 24 的整数倍 → "N 天"；其余 → "N 小时"
local function everyText(hours)
  local h = math.max(1, math.floor(tonumber(hours) or 24))
  if h % 24 == 0 then
    return string.format("%d 天", h // 24)
  end
  return string.format("%d 小时", h)
end


-- ==========================================================================
-- 图源：默认配置（首次运行写入 unsplashz_sources.json）
-- ==========================================================================
local DEFAULT_CONFIG_TEXT = [[
{
  "keyword": "nature",
  "sources": [
    {
      "name": "Unsplash API",
      "type": "json",
      "url": "https://api.unsplash.com/photos/random?orientation=landscape&query={keyword}&w={w}",
      "jsonPath": "urls.raw",
      "urlSuffix": "&w={w}&h={h}&fit=crop&q=80",
      "headers": { "Authorization": "Client-ID {key:unsplash}" },
      "note": "Unsplash 官方 API，需 Access Key（写入 ~/.hammerspoon/secrets/unsplash.key）；未配置时自动跳过"
    },
    {
      "name": "picsum",
      "type": "direct",
      "url": "https://picsum.photos/seed/{seed}/{w}/{h}",
      "note": "Unsplash 授权图库，免 key，按请求尺寸中心裁切"
    },
    {
      "name": "Bing",
      "type": "json",
      "url": "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8",
      "jsonPath": "images[].urlbase",
      "urlPrefix": "https://www.bing.com",
      "urlSuffix": "_UHD.jpg",
      "note": "微软每日壁纸，8 张随机取一（固定 16:9，会自动居中裁切）"
    }
  ]
}
]]

-- 内置默认图源（配置解析失败时的兜底）
local DEFAULT_SOURCES = {
  {name = "Unsplash API", type = "json",
   url = "https://api.unsplash.com/photos/random?orientation=landscape&query={keyword}&w={w}",
   jsonPath = "urls.raw", urlSuffix = "&w={w}&h={h}&fit=crop&q=80",
   headers = {["Authorization"] = "Client-ID {key:unsplash}"},
   note = "Unsplash 官方 API，需 Access Key"},
  {name = "picsum", type = "direct",
   url = "https://picsum.photos/seed/{seed}/{w}/{h}",
   note = "Unsplash 授权图库，免 key"},
  {name = "Bing", type = "json",
   url = "https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=8",
   jsonPath = "images[].urlbase", urlPrefix = "https://www.bing.com", urlSuffix = "_UHD.jpg",
   note = "微软每日壁纸"},
}

-- ==========================================================================
-- 图源设置规则（写入 unsplashz_sources.md，菜单可直接打开）
-- ==========================================================================
local RULES_TEXT = [[
<!-- 本文件由 UnsplashZ 自动生成，内容随版本更新，勿手动编辑 -->
# UnsplashZ · 图源设置规则

配置文件：`~/.hammerspoon/unsplashz_sources.json`（首次运行自动生成）
规则文档：`~/.hammerspoon/unsplashz_sources.md`（本文件）

菜单入口：菜单栏图标 → **图源设置**
- 点击图源名称 = 启用 / 禁用（状态存在 `unsplashz_prefs.json`，**不会改动你的配置文件**）
- **重新加载配置** = 改完 JSON 后点这个，无需重启 Hammerspoon
- **打开图源配置文件** = 用默认编辑器打开 JSON
- **测试所有图源** = 逐个试拉一张小图（320×200），只测不换壁纸

---

## 一、文件结构

```json
{
  "keyword": "nature",
  "sources": [ { ...图源1... }, { ...图源2... } ]
}
```

`keyword` 是检索关键词，会替换 URL 里的 `{keyword}` 占位符。
`sources` 是**数组**，按数组顺序依次尝试：**第一个成功的生效**，失败自动降级到下一个。

## 二、图源字段

| 字段 | 必填 | 说明 |
|---|---|---|
| `name` | 是 | 图源名称。菜单显示、日志记录、下载文件名前缀 |
| `type` | 否 | `direct` = URL 直接返回图片；`json` = 先取 JSON 再从里面取图片地址。默认 `direct` |
| `url` | 是 | 请求地址模板（见占位符表） |
| `jsonPath` | `type=json` 时必填 | 从 JSON 里取图片地址的路径（见第四节） |
| `urlPrefix` | 否 | 拼在图片地址**前面**（用于补全相对路径） |
| `urlSuffix` | 否 | 拼在图片地址**后面**（用于加尺寸参数、后缀名） |
| `headers` | 否 | 请求头。两种写法都支持：`{"Name":"Value"}` 或 `["Name: Value"]` |
| `enabled` | 否 | 是否启用，默认 `true` |
| `note` | 否 | 备注，菜单和日志里显示 |

## 三、占位符（可用在 `url` / `urlPrefix` / `urlSuffix` / 请求头的值里）

| 占位符 | 含义 |
|---|---|
| `{w}` | 目标宽度（像素）。自动模式下等于屏幕物理像素宽 |
| `{h}` | 目标高度（像素） |
| `{seed}` | 随机种子，**每次请求都不同**（picsum 这类"按 seed 出图"的接口必须用它，否则每次都是同一张） |
| `{keyword}` | 配置里的 `keyword` |
| `{index}` | 1~8 的随机整数 |
| `{date}` | 当天日期 `YYYYMMDD` |
| `{epoch}` | Unix 时间戳 |
| `{env:变量名}` | 读环境变量。**取不到就跳过这个图源**（不会白等一次 401） |
| `{key:名称}` | 读密钥，依次尝试：`~/.hammerspoon/secrets/名称.key` → 环境变量 `名称_ACCESS_KEY` → 环境变量 `名称`（自动转大写）。**取不到就跳过这个图源** |

## 四、jsonPath 语法（`type=json` 时用）

| 写法 | 含义 |
|---|---|
| `urls.raw` | 点号分层，逐层取字段 |
| `images[0].urlbase` | 下标从 **0** 开始 |
| `images[].urlbase` | 中括号留空 = 从这个数组里**随机挑一个**元素 |

取到的结果若不是字符串（例如数字），会自动转成字符串。
`urlPrefix` 会在图片地址前拼接，所以相对路径（如 `/th?id=...`）也能用。

## 五、运行规则

1. **回退链**：按 `sources` 数组顺序逐个尝试，第一个成功的图源用来设壁纸；全部失败则保持原壁纸不动。
2. **自动跳过**：含 `{key:...}` 或 `{env:...}` 却取不到值的图源会被直接跳过，不产生网络请求。
3. **比例修正**：图片宽高比与屏幕不符时，用 `sips` 做**居中裁切**修正（不会拉伸变形）；像素数不足目标时只在日志里提示，交给 macOS 缩放。
4. **改完即生效**：保存 JSON 后点菜单里的「重新加载配置」即可，不需要重启 Hammerspoon。
5. **不覆盖你的文件**：启停状态写在 `unsplashz_prefs.json`；只有主动点「重置为默认配置」才会覆盖 `unsplashz_sources.json`（覆盖前自动备份成 `.bak`）。
6. **JSON 写错不会崩**：解析失败时回退到内置默认图源，并在日志里写明原因。

## 六、内置的三个图源

| 名称 | 类型 | 说明 |
|---|---|---|
| Unsplash API | json | 官方 API，需 Access Key；未配置时自动跳过 |
| picsum | direct | `https://picsum.photos/seed/{seed}/{w}/{h}`，免 key，按请求尺寸裁切 |
| Bing | json | 微软每日壁纸，`images[].urlbase` 随机取一张，固定 16:9 会自动裁切 |

## 七、自己加图源的例子（下面几个都已实测可用）

**① 免 key，直连图片 CDN（type = direct）**

Unsplash 的图片 CDN 支持按 `w`/`h`/`fit=crop` 服务端裁切，输出正好是目标比例：

```json
{
  "name": "Unsplash CDN",
  "type": "direct",
  "url": "https://images.unsplash.com/photo-1506744038136-46273834b3fb?w={w}&h={h}&fit=crop&q=80",
  "note": "固定一张风景照（优胜美地湖），按屏幕比例服务端裁切"
}
```

换一张只要改 URL 中 `photo-` 后面那串 ID。

**② 免 key，按 seed 出图**

```json
{
  "name": "picsum",
  "type": "direct",
  "url": "https://picsum.photos/seed/{seed}/{w}/{h}"
}
```

`{seed}` 每次都变，所以每次都是不同的图。去掉 `{seed}` 就会永远返回同一张。

**③ 需要 API Key 的接口**

```json
{
  "name": "Wallhaven",
  "type": "json",
  "url": "https://wallhaven.cc/api/v1/search?categories=100&purity=100&atleast={w}x{h}&apikey={key:wallhaven}",
  "jsonPath": "data[].path",
  "headers": { "X-API-Key": "{key:wallhaven}" }
}
```

Key 放 `~/.hammerspoon/secrets/wallhaven.key`，一行一个值，不要引号。

**④ 按日期取固定图**

```json
{
  "name": "每日一图",
  "type": "direct",
  "url": "https://example.com/wallpaper/{date}.jpg"
}
```

**⑤ 接口返回的是相对路径时**

```json
{
  "name": "某壁纸站",
  "type": "json",
  "url": "https://example.com/api/random",
  "jsonPath": "data.image",
  "urlPrefix": "https://example.com"
}
```

`urlPrefix` 会拼在取到的地址前面，`data.image` 这种 `/xxx.jpg` 的相对路径也能用。

## 八、排查

| 现象 | 原因 |
|---|---|
| 日志显示「jsonPath 未命中」 | JSON 结构和配置的路径对不上，先用浏览器打开 `url` 看返回结构 |
| 日志显示「无法解析: key:xxx」 | 密钥没配。写到 `~/.hammerspoon/secrets/xxx.key` 或设同名环境变量 |
| 日志显示「请求头 Authorization 无法解析」 | 请求头里的占位符取不到值，该图源已被跳过 |
| 下载内容过小 (0B) | 返回的不是图片（比如错误页）。用 `curl -sSL -o /tmp/x.jpg "<url>"` 看返回内容 |
| 一直用第一个图源 | 第一个成功了就不会走后面的——想换就点菜单把第一个禁用 |
| 改了 JSON 没生效 | 忘了点「重新加载配置」 |
| 配了图源但菜单里看不到 | 该条目校验没过，日志里会有「图源 #N 已忽略: 原因」 |
]]


-- 该图源是否被用户禁用（菜单里点击切换；状态存在 prefs，不动用户的配置文件）
local function isSourceDisabled(name)
  for _, n in ipairs(obj.disabledSources or {}) do
    if n == name then return true end
  end
  return false
end

-- ==========================================================================
-- 内部工具
-- ==========================================================================
local function ensureDir()
  if not hs.fs.attributes(obj.dir) then
    hs.fs.mkdir(obj.dir)
  end
end

-- ==========================================================================
-- 偏好持久化（分辨率选择等）
-- ==========================================================================
local function loadPrefs()
  local fh = io.open(PREFSFILE, "r")
  if not fh then return end
  local body = fh:read("*a")
  fh:close()
  local ok, data = pcall(function() return hs.json.decode(body) end)
  if ok and type(data) == "table" then
    if data.sizeMode == "auto" or data.sizeMode == "manual" then
      obj.sizeMode = data.sizeMode
    end
    if tonumber(data.manualWidth) and tonumber(data.manualHeight) then
      obj.manualWidth  = tonumber(data.manualWidth)
      obj.manualHeight = tonumber(data.manualHeight)
    end
    if data.autoCleanup ~= nil then obj.autoCleanup = data.autoCleanup and true or false end
    if tonumber(data.retentionDays) then
      obj.retentionDays = math.max(1, math.floor(tonumber(data.retentionDays)))
    end
    if tonumber(data.cleanupEveryHours) then
      obj.cleanupEveryHours = math.max(1, math.floor(tonumber(data.cleanupEveryHours)))
    end
    -- 被禁用的图源名（用户点菜单禁用；不动他的配置文件）
    if type(data.disabledSources) == "table" then
      obj.disabledSources = {}
      for _, n in ipairs(data.disabledSources) do
        if type(n) == "string" and n ~= "" then
          obj.disabledSources[#obj.disabledSources + 1] = n
        end
      end
    end
  end
end

local function savePrefs()
  local data = {
    sizeMode = obj.sizeMode,
    manualWidth = obj.manualWidth,
    manualHeight = obj.manualHeight,
    autoCleanup = obj.autoCleanup,
    retentionDays = obj.retentionDays,
    cleanupEveryHours = obj.cleanupEveryHours,
    disabledSources = obj.disabledSources or {},
  }
  local ok, body = pcall(function() return hs.json.encode(data) end)
  if not ok or type(body) ~= "string" then return end
  local fh = io.open(PREFSFILE, "w")
  if fh then fh:write(body) fh:close() end
end

-- 切换分辨率模式 / 指定固定尺寸
-- mode = "auto"    → 跟随当前屏幕物理像素
-- mode = "manual"  → 使用 w×h（可传 nil 保留当前手动值）
function obj:setSize(mode, w, h)
  if mode == "auto" then
    obj.sizeMode = "auto"
    obj.autoFit  = true
  elseif mode == "manual" then
    obj.sizeMode = "manual"
    obj.autoFit  = false
    if w and h then
      obj.manualWidth  = math.floor(tonumber(w))
      obj.manualHeight = math.floor(tonumber(h))
      obj.width  = obj.manualWidth
      obj.height = obj.manualHeight
    end
  end
  savePrefs()
  local desc = obj.sizeMode == "auto" and "自动（跟随屏幕）"
    or string.format("手动 %d×%d", obj.manualWidth, obj.manualHeight)
  log("分辨率模式 → " .. desc)
  return self
end

-- 当前生效的目标描述（给菜单显示用）
function obj:sizeDescription()
  if obj.sizeMode == "manual" then
    return string.format("手动 %d×%d", obj.manualWidth, obj.manualHeight)
  end
  local g = buildTargets()
  if g[1] then
    return string.format("自动 %d×%d", g[1].pw, g[1].ph)
  end
  return "自动（未检测到屏幕）"
end

-- ==========================================================================
-- 屏幕适配
-- ==========================================================================
-- 壁纸画布 = 显示器完整显示区（含菜单栏）的物理像素。
-- hs.screen.currentMode() 给出 points 尺寸 + scale（如 2365x990 @2x），
-- 乘以 scale 得到真实像素（4730x1980），这才是壁纸该有的分辨率。
--
-- 关键：宽高比必须和屏幕一致，否则 macOS「适应」模式会留黑边、
-- 「填充」模式会裁掉两侧。像素数还要够，否则 Retina 下发虚。
local function detectScreens()
  local list = {}
  for _, s in ipairs(hs.screen.allScreens()) do
    local w, h, scale = nil, nil, nil
    local ok, mode = pcall(function() return s:currentMode() end)
    if ok and type(mode) == "table" and mode.w and mode.h then
      w, h, scale = mode.w, mode.h, (mode.scale or 1)
    else
      local okF, f = pcall(function() return s:fullFrame() end)
      if okF and f then w, h, scale = f.w, f.h, 1 end
    end
    if w and h and w > 0 and h > 0 then
      list[#list + 1] = {
        screen = s,
        name   = s:name(),
        pw     = math.floor(w * scale),   -- 物理像素宽
        ph     = math.floor(h * scale),   -- 物理像素高
        ratio  = w / h,                  -- 宽高比（用 points 算更准）
        scale  = scale,
      }
    end
  end
  return list
end

-- 把若干屏幕按「宽高比」归组：比例相同的共用一张壁纸，避免重复下载；
-- 比例不同的（如 16:9 外接屏 + 21:9 主屏）必须各来一张，否则必然有黑边。
buildTargets = function()
  local screens = detectScreens()
  if #screens == 0 then return {} end
  local groups = {}
  for _, sc in ipairs(screens) do
    local hit = nil
    for _, g in ipairs(groups) do
      local d = math.abs(g.ratio - sc.ratio) / g.ratio
      if d < 0.015 then hit = g break end   -- 1.5% 内视为同一比例
    end
    if hit then
      hit.screens[#hit.screens + 1] = sc
      -- 同组内取物理像素最大的那个作为目标，保证不糊
      if sc.pw * sc.ph > hit.pw * hit.ph then
        hit.pw, hit.ph, hit.ratio = sc.pw, sc.ph, sc.ratio
      end
    else
      groups[#groups + 1] = {
        ratio = sc.ratio, pw = sc.pw, ph = sc.ph, screens = {sc}
      }
    end
  end
  return groups
end

-- shell 单引号转义
local function shq(s)
  return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- 读取图片真实像素尺寸（sips 同步调用，几十毫秒）
local function imageSize(path)
  local out = hs.execute("/usr/bin/sips -g pixelWidth -g pixelHeight " .. shq(path))
  if type(out) ~= "string" then return nil end
  local w, h = out:match("pixelWidth:%s*(%d+)"), out:match("pixelHeight:%s*(%d+)")
  if w and h then return tonumber(w), tonumber(h) end
  return nil
end

-- 居中裁切到目标宽高比（sips -c 为中心裁切）。
-- 用于 Bing 这类固定 16:9 分辨率的兜底图源：裁掉多余部分得到正确比例，
-- 剩余像素不足由 macOS 缩放补齐（仅兜底路径会走到这里）。
local function cropToRatio(path, targetW, targetH)
  local aw, ah = imageSize(path)
  if not aw or not ah or aw == 0 or ah == 0 then return nil end
  local targetRatio = targetW / targetH
  local curRatio = aw / ah
  if math.abs(curRatio - targetRatio) / targetRatio < 0.01 then
    return aw, ah  -- 比例已经够准，不动
  end
  local nw, nh = aw, ah
  -- 注意方向：curRatio > target 表示「比目标更宽扁」，此时保留高度、裁掉两侧宽度；
  -- 反过来 curRatio < target 表示「比目标更竖高」，保留宽度、裁掉上下。
  -- （原先两个分支写反了，导致 3840x2160 裁成 3840x2160 的空操作。）
  if curRatio > targetRatio then
    nw = math.floor(ah * targetRatio)   -- 太宽 → 裁两侧
  else
    nh = math.floor(aw / targetRatio)   -- 太高 → 裁上下
  end
  nw = math.min(nw, aw); nh = math.min(nh, ah)
  if nw < 16 or nh < 16 then return nil end
  local ok = hs.execute(string.format("/usr/bin/sips -c %d %d %s --out %s >/dev/null 2>&1",
    nh, nw, shq(path), shq(path)))
  local rw, rh = imageSize(path)
  if rw and rh then return rw, rh end
  return nil
end

-- 读密钥：{key:名称} 的解析规则
--   1) ~/.hammerspoon/secrets/名称.key  文件（去掉所有空白）
--   2) 环境变量 名称_ACCESS_KEY
--   3) 环境变量 名称（全大写，非法字符换 _）
local function readSecret(name)
  if type(name) ~= "string" or name == "" then return nil end
  local base = name:gsub("[^%w]", "_"):upper()
  local keyPath = os.getenv("HOME") .. "/.hammerspoon/secrets/" .. name .. ".key"
  if hs.fs.attributes(keyPath) then
    local fh = io.open(keyPath, "r")
    if fh then
      local k = fh:read("*all")
      fh:close()
      k = (k or ""):gsub("%s+", "")
      if #k > 0 then return k end
    end
  end
  local env = os.getenv(base .. "_ACCESS_KEY")
  if env and #env > 0 then return env end
  env = os.getenv(base)
  if env and #env > 0 then return env end
  return nil
end

-- 用 curl 异步下载
local function download(url, filename, cb)
  ensureDir()
  -- 文件名去重：时间戳只到秒，同一秒内的并发或重试会撞名，
  -- 两个 curl 写同一个文件必然有一个失败（实测 curl exit 15）。
  local path = obj.dir .. "/" .. filename
  if hs.fs.attributes(path) then
    local base, ext = filename:match("^(.-)(%.[%w]+)$")
    base, ext = base or filename, ext or ""
    local n = 2
    repeat
      path = string.format("%s/%s_%d%s", obj.dir, base, n, ext)
      n = n + 1
    until not hs.fs.attributes(path) or n > 50
  end
  log("download 开始: " .. tostring(path:match("[^/]+$")))
  obj.task = hs.task.new("/usr/bin/curl", function(exitCode, stdOut, stdErr)
    if exitCode == 0 and hs.fs.attributes(path) then
      local sz = hs.fs.attributes(path).size or 0
      if sz > 1024 then
        cb(path, nil)
      else
        cb(nil, "下载内容过小 (" .. sz .. "B)")
      end
    else
      cb(nil, stdErr ~= "" and stdErr or ("curl exit " .. tostring(exitCode)))
    end
  end, {"-sSL", "--connect-timeout", "8", "--max-time", "35", "-A", UA, url, "-o", path})
  obj.task:start()
end

-- 应用到指定的一组屏幕（同一宽高比的屏幕共用一张图）
local function applyWallpaper(path, group)
  for _, sc in ipairs(group.screens) do
    sc.screen:desktopImageURL("file://" .. path)
  end
  obj.lastFile = path
  log(string.format("已设置壁纸 %s → %s", path, group.name))
end

-- ==========================================================================
-- 图源引擎（声明式，由 unsplashz_sources.json 驱动）
-- ==========================================================================
-- 一个图源由若干字段描述：
--   name       图源名（菜单显示 / 日志 / 文件名前缀）
--   type       direct = url 直接返回图片；json = 先取 JSON 再按 jsonPath 取图片地址
--   url        请求地址模板
--   jsonPath   type=json 时必填，支持 a.b.c / a[0].b / a[].b（[] = 数组随机取一个）
--   urlPrefix  拼在图片地址前（补全相对路径）
--   urlSuffix  拼在图片地址后（加尺寸参数等）
--   headers    请求头，支持 {"Name":"Value"} 或 {"Name: Value"} 两种写法
--   enabled    是否启用（菜单里的启停状态另存在 prefs 文件，不动用户配置）
--
-- 占位符：{w} {h} {seed} {keyword} {index} {date} {epoch} {env:VAR} {key:NAME}
-- 完整规则见 ~/.hammerspoon/unsplashz_sources.md

-- 模板渲染：把 {xxx} 换成实际值；取不到值的占位符视为错误（该图源跳过）
local function renderTemplate(tpl, ctx)
  if type(tpl) ~= "string" then return nil, "不是字符串" end
  local missing = {}
  local out = tpl:gsub("{([%w_:%-]+)}", function(token)
    local v
    if token == "w" then v = tostring(ctx.w)
    elseif token == "h" then v = tostring(ctx.h)
    elseif token == "seed" then v = ctx.seed
    elseif token == "keyword" then v = ctx.keyword
    elseif token == "index" then v = tostring(ctx.index)
    elseif token == "date" then v = os.date("%Y%m%d")
    elseif token == "epoch" then v = tostring(os.time())
    else
      local kind, nm = token:match("^(%a+):(.+)$")
      if kind == "env" then
        v = os.getenv(nm)
      elseif kind == "key" then
        v = readSecret(nm)
      end
    end
    if v == nil or v == "" then
      missing[#missing + 1] = token
      return ""
    end
    return tostring(v)
  end)
  if #missing > 0 then
    return nil, "无法解析: " .. table.concat(missing, ", ")
  end
  return out
end

-- jsonPath 取值：a.b.c / a[0].b
local function jsonPathGet(data, path)
  local cur = data
  for token in path:gmatch("[^%.%[%]]+") do
    if type(cur) ~= "table" then return nil end
    local v = cur[token]
    if v == nil then
      local n = tonumber(token)
      if n then v = cur[n] end
    end
    cur = v
    if cur == nil then return nil end
  end
  return cur
end

-- jsonPath 取值：a[].b —— 中括号留空表示从该数组里随机挑一个元素
local function jsonPathGetRandom(data, path)
  local head, tail = path:match("^(.-)%[%](.*)$")
  if not head then return nil end
  local arr = jsonPathGet(data, head)
  if type(arr) ~= "table" then return nil end
  local keys = {}
  for k in pairs(arr) do
    if type(k) == "number" then keys[#keys + 1] = k end
  end
  if #keys == 0 then return nil end
  local rest = arr[keys[math.random(1, #keys)]]
  if tail == nil or tail == "" then return rest end
  if tail:find("%[%]") then return jsonPathGetRandom(rest, tail) end
  return jsonPathGet(rest, tail)
end

-- 归一化一个图源定义：校验字段、补默认值
local function normalizeSource(spec, idx)
  if type(spec) ~= "table" then return nil, "不是对象" end
  local name = spec.name
  if type(name) ~= "string" or name == "" then
    return nil, "缺少 name"
  end
  local typ = spec.type or "direct"
  if typ ~= "direct" and typ ~= "json" then
    return nil, string.format("type 只能是 direct / json（%s）", tostring(spec.type))
  end
  if type(spec.url) ~= "string" or spec.url == "" then
    return nil, "缺少 url"
  end
  if typ == "json" and (type(spec.jsonPath) ~= "string" or spec.jsonPath == "") then
    return nil, "type=json 必须提供 jsonPath"
  end
  -- 请求头：{对象} 或 {"Name: Value" 数组} 都支持
  local headers = {}
  local raw = spec.headers
  if type(raw) == "table" then
    local isArray = #raw > 0
    for k, v in pairs(raw) do
      if isArray and type(k) == "number" then
        local hname, hval = tostring(v):match("^%s*([^:]+):%s*(.*)$")
        if hname then headers[hname] = hval end
      elseif type(k) == "string" then
        headers[k] = tostring(v)
      end
    end
  end
  return {
    name     = name,
    type     = typ,
    url      = spec.url,
    jsonPath = spec.jsonPath,
    urlPrefix = spec.urlPrefix,
    urlSuffix = spec.urlSuffix,
    headers  = headers,
    enabled  = (spec.enabled ~= false),
    note     = spec.note,
  }
end

local function normalizeList(list)
  local out = {}
  for i, spec in ipairs(list or {}) do
    local s, err = normalizeSource(spec, i)
    if s then
      out[#out + 1] = s
    else
      log(string.format("图源 #%d 已忽略: %s", i, tostring(err)))
    end
  end
  return out
end

local function readFile(path)
  local fh = io.open(path, "r")
  if not fh then return nil end
  local body = fh:read("*a")
  fh:close()
  return body
end

local function writeFile(path, body)
  local fh = io.open(path, "w")
  if not fh then return false end
  fh:write(body)
  fh:close()
  return true
end

-- 载入图源配置：文件不存在 → 写出默认配置 + 规则文档；解析失败 → 回退内置默认
local function loadSourceConfig()
  local body = readFile(SOURCESFILE)
  if not body then
    if writeFile(SOURCESFILE, DEFAULT_CONFIG_TEXT) then
      log("已生成默认图源配置: " .. SOURCESFILE)
    end
    body = DEFAULT_CONFIG_TEXT
  end
  -- 规则文档是自动生成的，内容有更新就同步一次
  if readFile(RULESFILE) ~= RULES_TEXT then
    if writeFile(RULESFILE, RULES_TEXT) then
      log("已同步图源规则文档: " .. RULESFILE)
    end
  end
  local ok, data = pcall(function() return hs.json.decode(body) end)
  if not ok or type(data) ~= "table" then
    log("图源配置解析失败，改用内置默认图源: " .. tostring(data))
    return normalizeList(DEFAULT_SOURCES)
  end
  local list = data.sources or data
  if type(list) ~= "table" then
    log("图源配置里没有 sources 数组，改用内置默认图源")
    return normalizeList(DEFAULT_SOURCES)
  end
  if type(data.keyword) == "string" and data.keyword ~= "" then
    obj.keyword = data.keyword
  end
  return normalizeList(list)
end

-- 下载文件名前缀：图源名里的特殊字符换成下划线
local function safeName(name)
  local s = tostring(name or "src"):gsub("[^%w%-_]", "_")
  if s == "" then s = "src" end
  return s
end

-- ==========================================================================
-- 按图源定义取图
-- ==========================================================================
-- cb(path, err)；opts.tag 用作文件名前缀（测试时传 "test"）
local function fetchSource(spec, tw, th, cb, opts)
  opts = opts or {}
  local ctx = {
    w       = tw,
    h       = th,
    seed    = "u" .. tostring(os.time()) .. tostring(math.random(1000, 9999)),
    keyword = obj.keyword,
    index   = math.random(1, 8),
  }
  local url, uerr = renderTemplate(spec.url, ctx)
  if not url then
    return cb(nil, "url " .. tostring(uerr))
  end
  -- 请求头里的占位符（密钥 / 环境变量）也要先解析
  local headers = {}
  for hname, hval in pairs(spec.headers or {}) do
    local hv, herr = renderTemplate(hval, ctx)
    if not hv then
      return cb(nil, string.format("请求头 %s %s", hname, tostring(herr)))
    end
    headers[hname] = hv
  end

  local function finishImageUrl(rawUrl)
    if type(rawUrl) ~= "string" or rawUrl == "" then
      return cb(nil, "图片地址为空")
    end
    local full = rawUrl
    if spec.urlPrefix then
      local p, perr = renderTemplate(spec.urlPrefix, ctx)
      if not p then return cb(nil, "urlPrefix " .. tostring(perr)) end
      full = p .. full
    end
    if spec.urlSuffix then
      local s, serr = renderTemplate(spec.urlSuffix, ctx)
      if not s then return cb(nil, "urlSuffix " .. tostring(serr)) end
      full = full .. s
    end
    local fname = string.format("%s%s_%dx%d_%s.jpg", opts.tag or "", safeName(spec.name),
      tw, th, os.date("%Y%m%d_%H%M%S"))
    download(full, fname, cb)
  end

  -- direct：URL 直接就是图片
  if spec.type == "direct" then
    return finishImageUrl(url)
  end

  -- json：先取 JSON，再按 jsonPath 取出图片地址
  hs.http.asyncGet(url, headers, function(status, body)
    if status ~= 200 or not body or body == "" then
      return cb(nil, "HTTP " .. tostring(status))
    end
    local ok, data = pcall(function() return hs.json.decode(body) end)
    if not ok or type(data) ~= "table" then
      return cb(nil, "JSON 解析失败")
    end
    local raw
    if spec.jsonPath:find("%[%]") then
      raw = jsonPathGetRandom(data, spec.jsonPath)
    else
      raw = jsonPathGet(data, spec.jsonPath)
    end
    if raw == nil then
      return cb(nil, "jsonPath 未命中: " .. spec.jsonPath)
    end
    finishImageUrl(tostring(raw))
  end)
end

-- ==========================================================================
-- 调度：按配置顺序回退
-- ==========================================================================
-- 注意：这里必须用**完整**的图源定义（含 headers / jsonPath / urlPrefix 等），
--       不能用菜单展示用的精简版，否则请求头和取值路径会丢。
local function buildSources()
  if not obj._sources then
    obj._sources = loadSourceConfig()
  end
  local active = {}
  for _, s in ipairs(obj._sources) do
    if s.enabled and not isSourceDisabled(s.name) then
      active[#active + 1] = s
    end
  end
  return active
end

-- 校验并按需校正比例：picsum / Unsplash 本身就是按目标尺寸裁好的，
-- 这里主要是兜住 Bing（固定 3840x2160，16:9）这种比例对不上的图源。
local function fitToTarget(path, tw, th)
  local aw, ah = imageSize(path)
  if not aw or not ah then
    log("尺寸读取失败，跳过校验: " .. path)
    return path
  end
  local wantRatio, gotRatio = tw / th, aw / ah
  if math.abs(gotRatio - wantRatio) / wantRatio > 0.015 then
    log(string.format("比例不符（实得 %dx%d，目标 %dx%d），本地居中裁切", aw, ah, tw, th))
    local cw, ch = cropToRatio(path, tw, th)
    if cw then
      aw, ah = cw, ch
    end
  end
  local note = ""
  if aw < tw or ah < th then
    note = string.format("（像素略小于屏幕 %dx%d，Retina 下可能略软）", tw, th)
  end
  log(string.format("尺寸校验: 实际 %dx%d / 目标 %dx%d %s", aw, ah, tw, th, note))
  return path
end

local function trySource(idx, tw, th, group, done)
  local sources = buildSources()
  if #sources == 0 then
    log("没有启用的图源（请在菜单「图源设置」里启用至少一个）")
    if done then done(nil) end
    return
  end
  if idx > #sources then
    log("全部图源失败")
    if done then done(nil) end
    return
  end
  local s = sources[idx]
  local settled = false
  fetchSource(s, tw, th, function(path, err)
    if settled then return end
    settled = true
    if path then
      obj.lastSource = s.name
      log("使用图源: " .. s.name)
      fitToTarget(path, tw, th)
      applyWallpaper(path, group)
      if done then done(path) end
    else
      -- 缺密钥属于「配置未就绪」而非故障，日志措辞区分开，
      -- 免得每轮都刷一行看着像报错。
      local e = tostring(err)
      if e:find("无法解析", 1, true) then
        log(string.format("%s 跳过（%s，未配置密钥）", s.name, e))
      else
        log(string.format("%s 失败: %s", s.name, e))
      end
      trySource(idx + 1, tw, th, group, done)
    end
  end)
end
-- ==========================================================================
-- 壁纸缓存清理
-- ==========================================================================
-- 策略：保留最近 N 天的壁纸，超期的删除；无论策略如何，至少保留最新 3 张，
--      避免误删导致「刚设的壁纸被当成旧图清掉」。
-- 执行：obj.cleanupEveryHours 小时跑一次（独立定时器），启动时也跑一次。
local function listCache()
  -- 注意：本机 Hammerspoon 的 hs.fs 是 lfs 语义：
  --   hs.fs.attributes(p) 返回 modification / size（不是 modificationDate），
  --   且没有 .dir 字段，hs.fs.dir 的迭代用法也不同。
  -- 因此这里用 /bin/ls 列目录，再用 attributes 取 mtime / size。
  local out = hs.execute("/bin/ls -1 " .. shq(obj.dir))
  local files = {}
  if type(out) ~= "string" then return files end
  for name in out:gmatch("[^\n]+") do
    if name ~= "." and name ~= ".." and name ~= "" then
      local p = obj.dir .. "/" .. name
      local a = hs.fs.attributes(p)
      if a and a.modification then
        files[#files + 1] = {path = p, date = a.modification, size = a.size or 0}
      end
    end
  end
  table.sort(files, function(a, b) return a.date > b.date end)
  return files
end

local function cleanupCache()
  if obj.autoCleanup == false then return 0, 0 end
  ensureDir()
  local files = listCache()
  local cutoff = os.time() - obj.retentionDays * 24 * 3600
  local removed, freed = 0, 0
  for i = 4, #files do                      -- 前 3 张永远保留
    local it = files[i]
    if it.date < cutoff then
      if os.remove(it.path) then
        removed = removed + 1
        freed = freed + it.size
      end
    end
  end
  if removed > 0 then
    log(string.format("清理完成: 删除 %d 张，释放 %.1f MB（保留 %d 天）",
      removed, freed / 1024 / 1024, obj.retentionDays))
  else
    log(string.format("清理检查: 无需删除（现有 %d 张，保留 %d 天）",
      #files, obj.retentionDays))
  end
  return removed, freed
end

-- 缓存统计（给菜单显示用）
function obj:cacheStats()
  local files = listCache()
  local size = 0
  for _, f in ipairs(files) do size = size + f.size end
  return #files, size
end

-- 设置清理策略
-- retentionDays   保留天数
-- everyHours      执行间隔（小时）；传 nil 表示不改变
function obj:setCleanup(retentionDays, everyHours, auto)
  if retentionDays then
    obj.retentionDays = math.max(1, math.floor(tonumber(retentionDays)))
  end
  if everyHours then
    obj.cleanupEveryHours = math.max(1, math.floor(tonumber(everyHours)))
  end
  if auto ~= nil then obj.autoCleanup = auto and true or false end
  savePrefs()
  -- 重启清理定时器
  if obj.cleanTimer then
    obj.cleanTimer:stop()
    obj.cleanTimer = nil
  end
  if obj.autoCleanup then
    obj.cleanTimer = hs.timer.doEvery(obj.cleanupEveryHours * 3600, function()
      cleanupCache()
    end)
    obj.cleanTimer:setNextTrigger(30)
  end
  log(string.format("清理策略 → %s，保留 %d 天，每 %s执行一次",
    obj.autoCleanup and "启用" or "关闭", obj.retentionDays,
    everyText(obj.cleanupEveryHours)))
  return self
end

-- 立即清理一次（忽略自动清理开关）
function obj:cleanupNow()
  local was = obj.autoCleanup
  obj.autoCleanup = true
  local removed, freed = cleanupCache()
  obj.autoCleanup = was
  return removed, freed
end

-- ==========================================================================
-- 图源管理
-- ==========================================================================

-- 当前图源列表（含启停状态），给菜单显示用
function obj:sourceList()
  if not obj._sources then
    obj._sources = loadSourceConfig()
  end
  local out = {}
  for i, s in ipairs(obj._sources) do
    local active = s.enabled
    if active and isSourceDisabled(s.name) then active = false end
    out[i] = {
      name    = s.name,
      type    = s.type,
      url     = s.url,
      note    = s.note,
      enabled = s.enabled,
      active  = active,
    }
  end
  return out
end

-- 启用 / 禁用某个图源（状态存 prefs，不动用户的配置文件）
function obj:setSourceEnabled(name, enabled)
  if type(name) ~= "string" or name == "" then return self end
  obj.disabledSources = obj.disabledSources or {}
  local out = {}
  for _, n in ipairs(obj.disabledSources) do
    if n ~= name then out[#out + 1] = n end
  end
  if enabled == false then
    out[#out + 1] = name
  end
  obj.disabledSources = out
  savePrefs()
  log(string.format("图源 %s → %s", name, enabled == false and "已禁用" or "已启用"))
  return self
end

-- 重新从配置文件读取图源
function obj:reloadSources()
  obj._sources = loadSourceConfig()
  local n = 0
  for _, s in ipairs(self:sourceList()) do if s.active then n = n + 1 end end
  log(string.format("图源配置已重新加载：共 %d 个，启用 %d 个", #obj._sources, n))
  return self
end

-- 重置为默认图源配置（覆盖前先备份用户的文件）
function obj:resetSources()
  local backup = SOURCESFILE .. ".bak"
  local cur = readFile(SOURCESFILE)
  if cur then writeFile(backup, cur) end
  if not writeFile(SOURCESFILE, DEFAULT_CONFIG_TEXT) then
    log("重置图源配置失败: 无法写入 " .. SOURCESFILE)
    return self
  end
  obj.disabledSources = {}
  savePrefs()
  obj._sources = loadSourceConfig()
  log("图源配置已重置为默认（原文件备份: " .. backup .. "）")
  return self
end

-- 逐个测试图源连通性：只拉一张 320×200 的小图，不换壁纸
-- 异步执行；传入 cb 则在全部测完后回调 cb(results)
-- results = { {name=, ok=, err=}, ... }
function obj:testSources(cb)
  local list = self:sourceList()
  local results = {}
  local idx = 0

  local function step()
    idx = idx + 1
    if idx > #list then
      local okCount = 0
      for _, r in ipairs(results) do if r.ok then okCount = okCount + 1 end end
      log(string.format("图源测试完成：%d/%d 可用", okCount, #results))
      if cb then pcall(cb, results) end
      return
    end
    local s = list[idx]
    if not s.active then
      results[#results + 1] = {name = s.name, ok = false, err = "已禁用"}
      log(string.format("[测试] %s: 已禁用，跳过", s.name))
      return step()
    end
    log(string.format("[测试] %s: 请求中…", s.name))
    -- 用归一化后的完整定义（sourceList 里是精简版）
    local spec = nil
    for _, full in ipairs(obj._sources or {}) do
      if full.name == s.name then spec = full end
    end
    if not spec then
      results[#results + 1] = {name = s.name, ok = false, err = "找不到定义"}
      return step()
    end
    fetchSource(spec, 320, 200, function(path, err)
      if path then
        local sz = hs.fs.attributes(path)
        os.remove(path)   -- 测试产物不留
        results[#results + 1] = {name = s.name, ok = true,
          err = string.format("OK（%d KB）", math.floor((sz and sz.size or 0) / 1024))}
        log(string.format("[测试] %s: 成功 %s", s.name,
          string.format("%d KB", math.floor((sz and sz.size or 0) / 1024))))
      else
        results[#results + 1] = {name = s.name, ok = false, err = tostring(err)}
        log(string.format("[测试] %s: 失败 %s", s.name, tostring(err)))
      end
      step()
    end, {tag = "test_"})
  end

  step()
  return results
end

-- ==========================================================================
-- 公共 API
-- ==========================================================================
function obj:init()
  ensureDir()
  loadPrefs()
  savePrefs()   -- 补全偏好文件缺失字段
  -- 载入图源配置（首次运行会生成默认配置与规则文档）
  obj._sources = loadSourceConfig()
  -- 清理定时器（独立于换图定时器）
  if obj.cleanTimer then obj.cleanTimer:stop() obj.cleanTimer = nil end
  if obj.autoCleanup then
    obj.cleanTimer = hs.timer.doEvery(obj.cleanupEveryHours * 3600, function()
      cleanupCache()
    end)
    obj.cleanTimer:setNextTrigger(30)
  end
  if obj.timer == nil then
    obj.timer = hs.timer.doEvery(obj.interval, function() obj:next() end)
    obj.timer:setNextTrigger(5)
  else
    obj.timer:start()
  end
  log("已启动，间隔 " .. math.floor(obj.interval / 3600) .. " 小时")
  -- 启动即报告一次分辨率适配情况
  if obj.sizeMode == "manual" then
    log(string.format("分辨率模式: 手动 %dx%d", obj.manualWidth, obj.manualHeight))
  else
    for _, g in ipairs(buildTargets()) do
      log(string.format("屏幕适配: %s 目标 %dx%d 比例 %.3f",
        g.screens[1].name, g.pw, g.ph, g.ratio))
    end
  end
  return self
end

function obj:next(opts)
  opts = opts or {}
  -- 并发保护：换图是一次异步过程（取 JSON → 下载 → 裁切 → 设置），
  -- 定时器与手动热键若在同一秒内都触发，两次下载会撞同一个文件名，
  -- 后一个写文件失败（实测 curl exit 15）并误报图源故障。
  if obj.busy then
    -- 手动按热键是有明确意图的，不能静默丢弃——记下来，当前任务结束后补跑。
    if opts.notify then
      obj.pending = obj.pending or {}
      obj.pending.notify = true
      log("已有换图任务进行中，本次手动请求已排队")
    else
      log("已有换图任务进行中，忽略本次定时请求")
    end
    return self
  end
  local token = tostring(os.time()) .. tostring(math.random(10000, 99999))
  obj.busy, obj.busyToken = true, token
  -- 兜底：极端情况下回调可能永不返回，超时解锁，避免永久卡死
  hs.timer.doAfter(240, function()
    if obj.busy and obj.busyToken == token then
      obj.busy, obj.busyToken = false, nil
      log("换图任务超时未完成，已解锁")
      if obj.pending then
        local again = obj.pending
        obj.pending = nil
        hs.timer.doAfter(1, function() obj:next(again) end)
      end
    end
  end)
  log("next() 进入 · " .. (opts.notify and "手动" or "定时"))
  if obj.task then
    obj.task:terminate()
    obj.task = nil
  end
  if not opts.quiet then
    log(opts.notify and "手动触发换图…" or "定时触发换图…")
  end

  -- 分辨率来源：auto = 跟随屏幕物理像素；manual = 用户指定的固定尺寸
  local targets
  if obj.sizeMode == "manual" then
    local w, h = obj.manualWidth, obj.manualHeight
    targets = {{
      ratio = w / h,
      pw = w, ph = h,
      screens = detectScreens(),
    }}
    log(string.format("手动分辨率: %dx%d（比例 %.3f）", w, h, w / h))
  else
    targets = buildTargets()
  end
  if #targets == 0 then
    log("未检测到可用屏幕，跳过")
    return self
  end
  for i, g in ipairs(targets) do
    local sn = g.screens[1] and g.screens[1].name or "所有屏幕"
    g.name = string.format("%s(%dx%d)", sn, g.pw, g.ph)
    log(string.format("目标屏幕组 %d/%d: %s  比例 %.3f", i, #targets, g.name, g.ratio))
    -- 手动模式下若比例与屏幕不符，提示可能出现黑边/裁切
    if obj.sizeMode == "manual" then
      for _, sc in ipairs(g.screens) do
        local d = math.abs(sc.ratio - g.ratio) / sc.ratio
        if d > 0.02 then
          log(string.format("  提示: %s 屏幕比例 %.3f 与所选分辨率不匹配，"
            .. "可能出现黑边或裁切（macOS 壁纸显示模式：适应/填充）", sc.name, sc.ratio))
        end
      end
    end
  end

  local idx, okCount = 0, 0
  local function step()
    idx = idx + 1
    if idx > #targets then
      if obj.busyToken == token then
        obj.busy, obj.busyToken = false, nil
      end
      log(string.format("换图完成：%d/%d 个屏幕组成功", okCount, #targets))
      if opts.notify then
        -- 换图完成，给用户明确反馈（避免以为没反应）
        -- 注意：本版本 hs.notify 没有 :inform()，只有 :informativeText()；
        -- 用 pcall 包住，通知失败绝不影响已经完成的壁纸设置。
        pcall(function()
          hs.notify.new()
            :title("UnsplashZ")
            :informativeText(string.format("壁纸已更新（%s）", tostring(obj.lastSource)))
            :send()
        end)
      end
      -- 排队的手动请求：当前这轮结束后补跑一次
      if obj.pending then
        local again = obj.pending
        obj.pending = nil
        log("执行排队中的换图请求")
        hs.timer.doAfter(0.5, function() obj:next(again) end)
      end
      return
    end
    local g = targets[idx]
    trySource(1, g.pw, g.ph, g, function(path)
      if path then okCount = okCount + 1 end
      step()
    end)
  end
  step()
  return self
end

function obj:stop()
  if obj.timer then
    obj.timer:stop()
    log("定时器已停止")
  end
  if obj.cleanTimer then
    obj.cleanTimer:stop()
    obj.cleanTimer = nil
    log("清理定时器已停止")
  end
  if obj.task then
    obj.task:terminate()
    obj.task = nil
  end
  return self
end

-- 暴露内部引用，确保外部拿到的就是同一个实例（避免副本导致状态不同步）
obj.self = obj
obj.getObj = function() return obj end

return obj
