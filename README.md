# 旗鱼搜索 / Sailfish Everything

超快的 Mac 本地硬盘文件搜索工具。

如果你知道 Everything 软件的话，这就是 Mac 上的 Everything。

打开 `dist/Sailfish Everything.dmg`，把软件拖进应用程序文件夹。从安装盘或下载文件夹直接打开时，软件也会问要不要放到那里。若系统提示无法打开，按住 Control 点图标，再选打开。

```bash
bash scripts/run.sh     # 打包、装进应用程序并打开
bash scripts/test.sh    # 跑测试
```

构建需要 Xcode 命令行工具和 Swift 6。

支持 macOS 14 或更高版本。

---

## Sailfish Everything

Blazing-fast local file search for Mac.

If you know Everything on Windows, this is that for Mac.

Open `dist/Sailfish Everything.dmg` and drag the app into Applications. If you open it from the disk image or Downloads, it will offer to move there. If macOS says it can’t be opened, Control-click the app and choose Open.

```bash
bash scripts/run.sh     # package, install to Applications, and open
bash scripts/test.sh    # run tests
```

Requires Xcode Command Line Tools and Swift 6.

Supports macOS 14 or later.
