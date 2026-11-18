<div align="center">

<img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png" width="120" alt="影片庫 icon">

# 影片庫 (GuoApp)

A Flutter short-drama streaming app, with dedicated layouts for phones, tablets, desktops and TVs.

[![Release](https://img.shields.io/github/v/release/gentoobreaking/guoapp?style=flat-square&color=3d4656)](https://github.com/gentoobreaking/guoapp/releases)
[![License](https://img.shields.io/badge/license-GPL--3.0-3d4656?style=flat-square)](LICENSE)
![Flutter](https://img.shields.io/badge/Flutter-3.47.9-02569B?style=flat-square&logo=flutter&logoColor=white)
![Platforms](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS-8fa3bc?style=flat-square)

English · [繁體中文](README.zh-TW.md) · [简体中文](README.zh-CN.md)

[Features](#features) · [Fork changes](#what-this-fork-adds) · [Installation](#installation) · [Privacy](#update-checks--anonymous-statistics) · [Development](#development)

</div>

---

This repository is a fork of [Xanerix/guoapp](https://github.com/Xanerix/guoapp), which in turn was adapted from the source code of [fish2018](https://github.com/fish2018). The hongguo source module ships with official packages; other sources install as modules from the in-app **Modules** store.

> [!WARNING]
> The project is under active development. User data is not guaranteed and may be lost when upgrading between versions.

## What this fork adds

Differences from upstream as of version 2.0.1 (Nov 2026):

- **Downloads on Android TV** — upstream excludes TV devices from downloads. This fork brings the full download flow to TV: an entry in *Mine*, download queue and library pages laid out with TV overscan-safe margins, and D-pad friendly dialogs for batch and range selection.
- **Multi-episode preload** — beyond pre-buffering the next episode, a 「预载为完整下载」(preload as full download) mode fully downloads upcoming episodes in watch order (1–5 episodes ahead) so playback keeps going on weak or offline networks. Scheduling is idempotent and skips VIP episodes according to download preferences.
- **Tunable resource settings** — admin settings for HLS segment concurrency (1–8), prefetch size (4/8/16 MB) and catalog request concurrency (1–6), persisted in the Go core and applied to downloads, prefetch and catalog requests.
- **Audio focus (Android)** — the player requests proper audio focus and pauses on transient loss (including duck requests); only focus-caused pauses auto-resume; focus is abandoned when leaving the player. Picture-in-picture and audio focus share one native callback dispatcher.
- **Faster episode switching** — preloaded plans trust the source's stated credential expiry (capped at 10 minutes) instead of being discarded early; a 25-second watchdog cancels and retries a stuck media resolution; a 「重新获取」(re-resolve) button appears after 12 seconds of loading.
- **Quality filter** — the clarity menu only lists 720P and above (auto still falls back). The *Discover* list offers 全部画质 / 720P+ / 1080P filters based on per-drama quality learned locally (recorded on playback, plus one background probe of the first episode when a detail page is opened).
- Misc: Gradle wrapper switched to the `-bin` distribution, Android Gradle Plugin 9.1.1.

Source catalogs do not publish video quality, so the list filter works from these locally observed records — dramas you have not played or opened yet are hidden while a filter is active.

## Features

### Interface & appearance

- **Navigation**: 发现 (Discover) / 追剧 (Following) / 我的 (Mine). Phones use a bottom bar, tablets and desktops a sidebar (collapsible), TVs a top tab bar; on wide screens sub-pages open to the right of the sidebar.
- **UI modes**: automatic, TV, phone, tablet, window (desktop only); once chosen manually it no longer follows window width. TV mode forces landscape, phone mode locks portrait.
- **Themes**: follow-system color (Android 12+ from wallpaper, Windows/macOS from accent color) or 6 preset palettes; light / dark / follow system.

### Browsing

- **Discover**: switch sources next to the source name; category tabs are recommendations / all / rankings / genres, with rank numbers on ranking covers. The first tab shows a large card for the most recent or recommended drama. Endless scroll, pull-to-refresh. A quality filter (全部画质 / 720P+ / 1080P, fork addition) can narrow the list to dramas with known high-resolution sources.
- **Search**: searches the current source only, keeps recent searches; hongguo provides input suggestions.
- **Details**: blurred cover backdrop, episode count, completion status, category, views, tags and synopsis; 30 episodes per group, opened at the resume episode, watched episodes dimmed, VIP episodes marked. Pre-buffers the resume episode in the background. Opening a detail page also silently records the drama's source quality for the list filter.

### Playback

| Device | Experience |
| --- | --- |
| Desktop | Video left, episode list right; widescreen and fullscreen supported; hover menus for clarity, speed and volume; keyboard shortcuts (Space, Enter, arrows, Page Up / Down, M, …) |
| Phone | Portrait immersive mode: swipe vertically for next/previous episode, horizontal swipe to seek, long-press the picture for playback settings, long-press sides for 2× playback (speed configurable), lockable. Landscape videos show the picture on top and synopsis / episodes below, rotating to landscape goes fullscreen; in fullscreen, double-tap sides to seek, left half swipes brightness, right half volume |
| Tablet | Landscape behaves like desktop, portrait like phone; fullscreen locks landscape |
| TV | Controls float over the picture; when hidden, left/right keys seek 10 seconds; back closes options, then controls, then exits; episode changes return to the detail page |

Common to all devices: the next episode is pre-buffered so page turns and continuous play connect seamlessly; speed, clarity and danmaku toggles are remembered. Hongguo streaming has danmaku; local playback does not. On Android the player cooperates with other audio apps via audio focus (fork addition).

### Following & history

- **Following**: just following / not following. Dramas with new episodes sort under "有更新" (updated) with the new episode count; searchable, filterable by source, multi-select unfollow. A background job checks a batch of unfinished dramas every 30 minutes.
- **History**: grouped into today / yesterday / earlier; searchable, filterable by source, multi-select delete; "清空" (clear) only clears the listed items.
- **Mine**: user card, recent watching, download summary and settings entry; the tab/sidebar icon shows how many episodes are downloading. Includes a download entry that opens the queue and downloaded library.

### Downloads

- Start from the detail page's 「下载选集」 or multi-select in the player's episode list (tap, drag, select all).
- The downloads page splits into 「下载中」 (downloading) and 「已下载」 (downloaded), with pause / resume / retry per episode or for all; downloaded dramas can be played, deleted or topped up with missing episodes. Available on all form factors **including TV** (fork addition).
- Each finished episode is automatically converted to a plain mp4 (hongguo is decrypted first, then the m3u8 is merged into one file) and saved as `download dir/drama title/第 N 集.mp4`, ready to copy out.
- Episodes downloaded by older versions stay as-is; files merged by those versions are no longer listed.

### Settings, users & backup

- **Settings**: 9 groups — appearance, playback, danmaku, download, storage, proxy, users, about, diagnostics — saved immediately; items you lack permission for are greyed out with a reason.
- **Users**: separate following, history and searches per user, switch with a tap; admins add, edit and delete users and control which sources each can access and whether downloads are allowed.
- **Backup**: export / restore users, following, history and preferences (including theme color); downloaded videos are unaffected; older backups still import. If local configuration is damaged, the startup screen can restore from a backup.

## Installation

Packages built from this fork are currently distributed as source builds — check the [Releases](https://github.com/gentoobreaking/guoapp/releases) page; prebuilt packages of the upstream project are on the [upstream Releases](https://github.com/Xanerix/guoapp/releases) page. `[NEEDS VERIFICATION: whether/when this fork will publish its own release packages]`

Building the Android app from source:

```sh
python3 scripts/build_native.py --platform android --abi arm64-v8a   # or armeabi-v7a / x86_64
python3 scripts/build_android.py                                     # all three ABIs
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for other platforms, module bundling (`--bundle`) and the release workflow.

| Platform | Packages |
| --- | --- |
| Android 7.0+ | arm64-v8a / armeabi-v7a / x86_64 APKs — pick by device architecture (most phones: arm64-v8a; many TVs: armeabi-v7a); same signature upgrades in place |
| Windows 10/11 x64 | Installer `*-setup.exe` (per-user, no admin needed) or portable ZIP; portable builds keep settings and downloads in `userdata` next to the executable |
| iOS 15.1+ | Unsigned IPA, self-sign or sideload |
| macOS 12+ | Universal dmg (Apple silicon & Intel), not notarized — remove quarantine on first launch |

> [!TIP]
> On Android, `INSTALL_FAILED_NO_MATCHING_ABIS` means the APK does not match the device architecture; pick the matching package.

> [!IMPORTANT]
> For macOS, run before first launch:
>
> ```sh
> xattr -dr com.apple.quarantine /Applications/影片庫.app
> ```

## Update checks & anonymous statistics

| Request | Data sent |
| --- | --- |
| Update check | Nothing is uploaded; only the latest version number is read. Checked once at startup, with an optional ignore / never remind |
| Anonymous usage statistics | Only: a random ID generated at first report (unrelated to device or account), app version, platform (Android / iOS / Windows / macOS), build id (fixed `guoapp`) |

No watch history, following, searches, source settings or any other personal data is sent. The receiver code lives in [`worker/`](worker). Both can be turned off separately in **Settings › About**. The statistics endpoint URL is injected at build time (`UPDATE_SERVER_URL`); when unset — as in local and fork builds without it — the app sends nothing at all.

## Disclaimer

The app shows the following terms on first launch and requires consent before use:

- This project is open-source software; the framework and the source modules in the module store are public. It is for personal study and technical research only, **free of charge, with no paid service**.
- This project is **not affiliated with** Hongguo Short Drama or any other source operator, and has no endorsement from them; names and trademarks belong to their owners.
- The app **does not store, upload or distribute any media content**; all content comes from third-party sites and remains copyrighted by its owners. The app does not bypass source VIP or other authorization.
- Except for the bundled hongguo source, sources are installed by the user as modules; modules access the third-party sites listed at install time. **Modules installed from files or URLs are not vetted by the module store — only install trusted modules, and the consequences are the installer's responsibility.**
- Content watched or downloaded through the app is for trial viewing and personal study; **delete within 24 hours of downloading**, and support the official releases.
- **Do not promote or share the app, its packages, download links, or the content obtained through it on any public platform** (social media, short-video platforms, forums, public groups, etc.).
- Source content (including ads, links, QR codes and contact info) is provided by third parties; **verify it yourself and never trust requests for payment, investment, gambling or part-time jobs; the author is not liable for any resulting losses**.
- Watch history, following and download data stay on the device; see [Update checks & anonymous statistics](#update-checks--anonymous-statistics) for what is sent online.
- Users must comply with local laws and each site's terms of service; **the app must not be used for illegal or commercial purposes; all consequences of using this project are borne by the user**.
- This project is provided "as is", with no warranty of availability, stability or fitness; **the author is not liable for any direct or indirect losses**.
- If you disagree with these terms, **stop using and uninstall the app immediately**.
- If you believe this project infringes your rights, contact us via an Issue; confirmed cases will be handled promptly.

## License

This project is released under [GNU GPL v3.0](https://www.gnu.org/licenses/gpl-3.0.html); see [LICENSE](LICENSE) for the full text. Third-party dependencies follow their own licenses (the bundled FFmpegKit min-gpl build includes GPL media components).

## Development

Build, test, architecture and release instructions: [DEVELOPMENT.md](DEVELOPMENT.md). Contributing and writing community source modules: [CONTRIBUTING.md](CONTRIBUTING.md). Version history: [CHANGELOG.md](CHANGELOG.md).

## Acknowledgements

- [fish2018](https://github.com/fish2018) — author of the original source code
- [Xanerix/guoapp](https://github.com/Xanerix/guoapp) — the upstream project this fork is based on
