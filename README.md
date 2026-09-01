# 旗鱼搜索 / Sailfish Everything

Mac 上的文件名搜索。记得几个字，立刻摊开所有对得上的文件。只认文件名和路径，不搜正文，不走系统搜索。

[English](#sailfish-everything)

---

## 旗鱼搜索

从 Windows 用惯了 Everything，换到 Mac 之后，系统搜索会把正文、邮件、词典混进来，结果窗又只露一条缝。旗鱼搜索做的是那一下：**边敲边出，结果铺成一张大表，靠路径自己认。**

这是独立软件，不是旗鱼里的一个功能。

### 它做什么

- 打开就能敲，不必按回车
- 结果是一张表，名称和路径同时看得见
- 只扫个人文件夹里本机已经有的文件
- iCloud、OneDrive 这类云盘默认不扫（太慢）；要搜，去设置的排除列表里去掉
- 外置盘要搜，在设置里另外加
- 关窗口不会退出，菜单栏和热键还能唤回

### 它不做什么

不当启动器，不搜正文，不套系统搜索。Windows 上已有 Everything，这里只做 Mac。

### 要求

- macOS 14 或更新
- 要搜全个人文件夹里受保护的位置，请在系统设置里打开「完全磁盘访问」

### 运行

```bash
bash scripts/run.sh
```

会打包出 `dist/Sailfish Everything.app` 并打开。也可以只打包：

```bash
bash scripts/package.sh
```

源码构建需要 Xcode 命令行工具和 Swift 6。

### 测试

```bash
bash scripts/test.sh
```

### 文档

讨论里确认过的设计在 SPEC 里，不在这份说明里展开：

- [产品](docs/specs/产品.md)
- [窗口与使用](Sources/SailfishEverything/SPEC.md)
- [名单与搜索](Sources/SailfishEverythingCore/SPEC.md)

还没做成方案的点子在 [想法本](docs/ideas.md)。

---

## Sailfish Everything

Filename search for Mac. Type a few characters and see every matching file in a full table. Names and paths only — not file contents, not Spotlight.

This is a standalone app, not a feature of Sailfish.

### What it does

- Results update as you type. No need to press Return
- A full table of matches, with names and paths visible together
- Indexes files already on disk in your home folder
- Skips cloud drives such as iCloud and OneDrive by default (they are too slow). Remove them from the exclude list in Settings if you want them
- Extra disks can be added in Settings
- Closing the window hides the app; the menu bar and hotkey bring it back

### What it is not

Not a launcher. Not full-text search. Not a Spotlight wrapper. Windows already has Everything; this project is Mac-only.

### Requirements

- macOS 14 or later
- For complete coverage of protected folders in your home directory, grant Full Disk Access in System Settings

### Run

```bash
bash scripts/run.sh
```

This packages `dist/Sailfish Everything.app` and opens it. To package only:

```bash
bash scripts/package.sh
```

Building from source needs Xcode Command Line Tools and Swift 6.

### Test

```bash
bash scripts/test.sh
```

### Docs

Confirmed design lives in the SPECs, not in this README:

- [Product](docs/specs/产品.md) (Chinese)
- [Window and use](Sources/SailfishEverything/SPEC.md) (Chinese)
- [Index and search](Sources/SailfishEverythingCore/SPEC.md) (Chinese)

Unverified ideas go in [docs/ideas.md](docs/ideas.md).
