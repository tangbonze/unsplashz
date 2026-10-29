# UnsplashZ.spoon

[中文](README.md) · **English**

Random landscape wallpapers for [Hammerspoon](https://www.hammerspoon.org/): picks images at your screen's true pixel size, with a configurable source chain and automatic cache cleanup.

> Based on UnsplashZ from [Hammerspoon/Spoons](https://github.com/Hammerspoon/Spoons) by ashfinal (MIT).
> The upstream `source.unsplash.com` endpoint was retired by Unsplash in mid-2024 (now returns HTTP 503), so the download path was rewritten.

## What changed

| | Upstream | This fork |
|---|---|---|
| Fetching | `source.unsplash.com` (dead) | **Declarative source chain** in JSON, auto-failover |
| Sources | Unsplash only | Unsplash API / picsum / Bing, plus any custom endpoint |
| Size | Fixed | **Follows real screen pixels** (via `currentMode()`, no Retina blur) |
| Multi-display | No | Grouped by aspect ratio, same ratio shares one image |
| Cache | Grows forever | Age-based cleanup, retention configurable |
| Menu bar | Text | **SF Symbols template image**, auto-inverts in light/dark |

## Install

```bash
git clone https://github.com/tangbonze/unsplashz.git
cd unsplashz
./install.sh
```

The script only copies `UnsplashZ.spoon` into `~/.hammerspoon/Spoons/` and prints the snippet to paste into your own `init.lua` — it never rewrites your config.

Manual install:

```bash
cp -R UnsplashZ.spoon ~/.hammerspoon/Spoons/
```

Then append to `~/.hammerspoon/init.lua`:

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

Reload the config and a menu bar icon appears.

## Usage

| Entry | Action |
|---|---|
| `⌃⌥W` | Change wallpaper now |
| Menu bar icon | Menu: change / resolution / cleanup / sources |
| Timer | Every 3 hours by default |

## Resolution matching

In auto mode the plugin reads `hs.screen:currentMode()` and multiplies `width × scale` to get **physical pixels**. A 3440×1440 display reporting `2365×990 @2x` gets a `4730×1980` wallpaper — exact canvas size, no upscaling blur.

You can also pick one of 12 common resolutions manually (1920×1080 through 5120×2880). If the selected ratio differs from the screen by more than 2%, the log warns about letterboxing or cropping.

Multiple displays are grouped by aspect ratio; identical ratios share one download.

## Configuring sources

`~/.hammerspoon/unsplashz_sources.json` is generated on first run. Edit it, then hit "reload config" in the menu — no restart needed.

Minimal example (endpoint returns an image directly):

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

Two-step example (JSON first, image URL inside):

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

`[]` in `jsonPath` means "pick a random element". Full field table, placeholders and troubleshooting: **[docs/sources.md](docs/sources.md)** (Chinese).

## Where to put API keys

**Never in the JSON.** Use the `{key:name}` placeholder; lookup order:

1. `~/.hammerspoon/secrets/name.key` (single line, no quotes)
2. Environment variable `NAME_ACCESS_KEY`
3. Environment variable `NAME` (upper-cased)

Missing keys cause that source to be skipped, not an error.

## Menu bar icon

Default is `photo.stack`, rendered from SF Symbols into an 18pt@2x template PNG via Swift. To switch:

```bash
~/.hammerspoon/icons/set_icon.sh mountain.2.fill
```

The second argument to `setIcon(image, true)` is the template flag — **that's what makes the icon invert with the menu bar**. It also hot-reloads Hammerspoon.

## Known limitations

- Hammerspoon needs **Accessibility permission** for the hotkey.
- On macOS 27, synthetic key events (`hs.eventtap.keyStroke`, AppleScript) never reach Hammerspoon, so hotkeys can't be verified by script — test them by hand.
- This build's `hs.fs` is lfs-flavoured (`attributes().modification`, no `modificationDate`) and lacks `hs.image.imageFromSymbol`, hence the Swift icon renderer.
- Bing caps at 3840×2160, slightly soft on 5K screens (it is center-cropped to the correct ratio locally).

## License

MIT — see [LICENSE](LICENSE). Original copyright belongs to ashfinal.
