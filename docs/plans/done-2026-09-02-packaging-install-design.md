# 已完成 · 2026-09-02 打包与安装

按成熟 Mac 软件的标准，让人能从盘镜拖进应用程序文件夹，包装完整，从临时位置打开时能装到正确地方。

## 改哪些

- `Sources/SailfishEverything/SPEC.md`：安装设计目标
- `scripts/package.sh`：通用二进制、硬化运行时、盘镜窗口
- `Resources/SailfishEverything.entitlements`、`Resources/PrivacyInfo.xcprivacy`、`Resources/Info.plist`：包装信息
- `Sources/SailfishEverything/AppInstall.swift`、`App.swift`：从盘镜/下载打开时询问
- `Sources/SailfishEverythingCore/L10n.swift`：文案
- `README.md`：怎么装
- 测试与 `scripts/test.sh`：包装验收

## 怎么做

- 发布包打 arm64 + x86_64，带硬化运行时；有 `SIGN_IDENTITY` / `NOTARIZE_PROFILE` 才走开发者签名和公证，否则 ad-hoc
- 盘镜里放应用和应用程序文件夹的快捷方式，打开窗口时左右摆好；排版失败仍要出能用的盘
- 从 `/Volumes`、下载或门禁转移目录打开才问要不要拷到应用程序；`.build`、已在应用程序里、自动化不问
- 不做 Sparkle、不做 pkg、不做沙盒

## 任务拆解

- [x] 包装带通用二进制、权限声明、隐私清单、硬化运行时
- [x] 盘镜打开能拖进应用程序，图标摆好
- [x] 从盘镜或下载打开时能装进应用程序文件夹
- [x] README 写清怎么装；`bash scripts/test.sh`
