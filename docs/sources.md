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
