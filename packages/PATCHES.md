# 本地覆盖的依赖包（dependency_overrides）

`pubspec.yaml` 的 `dependency_overrides` 用本目录三个包替换了上游版本。
每个包的 `version` 都带 `+duanju.N` 后缀标记本地修改；升级上游时，先对照下表
重新 diff 并更新后缀编号，确认无遗漏再合入。

| 包 | 本地版本 | 上游 | 引入 commit | 原因 |
| --- | --- | --- | --- | --- |
| `media_kit_video` | `2.0.1+duanju.1` | [media-kit/media-kit](https://github.com/media-kit/media-kit) `media_kit_video` | `fd3a417` | Windows 关闭播放器前先同步释放视频画面的渲染上下文，修复退出播放页几秒后闪退（#116）。整包 vendored（含 android/common/ios 平台代码） |
| `media_kit_libs_windows_video` | `1.0.11+duanju.1` | 同仓库 `media_kit_libs_windows_video` | `0d2a752` 前后 | Windows 构建的 libmpv 和 ANGLE 改从本仓库 `windows-native-deps` release 下载，上游 mpv-winbuild-cmake 已删除所需版本 |
| `shared_preferences_windows` | `2.4.1` | [flutter/packages](https://github.com/flutter/packages) `shared_preferences_windows` | `dfe95b9` | Windows 设置文件改为先写临时文件再替换并保留上一版，文件损坏时回退上一版，修复断电后打开报 `FormatException` |

## 升级上游的步骤

1. 找到当前 vendored 包对应的 upstream tag（看 `pubspec.yaml` 里 `version` 的主版本与
   `CHANGELOG`），clone 上游仓库到临时目录。
2. `diff -ru upstream/<package> packages/<package>` 逐文件过一遍本地改动；
   实际本地改动应只有上表所述内容（外加版本号的 `+duanju.N` 后缀）。
3. 若上游已包含等价修复，直接删掉对应 `dependency_overrides` 条目和目录；
   否则把本地补丁重新套到新版本上，`version` 的 `+duanju.N` 编号加一。
4. 跑 `flutter test` 与全平台出包验证后再提交。

## 注意

- 这些目录**不是**第三方 fork 的持续镜像，是按需 vendored 的快照——不要随手在里面加新功能；
  任何新改动都要更新本文件并在 commit message 里说明原因。
- `DEVELOPMENT.md` 的「目录说明」表只列了其中一个包，本文件是三个覆盖的完整清单。
