# 已完成 · 2026-09-02 诊断记录

卡住之后能翻一份一直在记的记录，对上当时是扫盘、在筛，还是窗口在刷新名单。

## 改哪些

- `Sources/SailfishEverythingCore/SPEC.md`、`Sources/SailfishEverything/SPEC.md`：设计目标
- `Sources/SailfishEverythingCore/DiagnosticLog.swift`：写入、轮换
- `Sources/SailfishEverythingCore/Scanner.swift`：扫盘节点
- `Sources/SailfishEverything/MainWindowController.swift`：筛、刷新、状态栏
- `Sources/SailfishEverything/App.swift`：菜单打开记录
- `Sources/SailfishEverythingCore/L10n.swift`：文案
- `Tests/SailfishEverythingTests/DiagnosticLogTests.swift`：写入与轮换

## 怎么记

一行一件事，带时间。主题只有 `session` / `scan` / `search` / `table`。

- 扫盘：开始、换阶段、约每 2 秒一条进度、收尾（合并、路径、预热）、结束或失败
- 搜索：开始（关键字、是否还在扫）、结束（命中数、耗时）；被下一轮挤掉也记
- 刷新：`reloadData` 的开始/结束和耗时；扫盘中途改行数只在超过约 50ms 时记
- 文件在用户日志目录，超过约 512KB 只留后半；自动化和测试默认不写真实日志

## 任务拆解

- [x] 诊断记录能写下事件，关掉不写，过长丢掉旧的
- [x] 扫盘节点进记录
- [x] 敲字筛名单、刷新列表进记录；正在筛时状态栏能看出来
- [x] 帮助菜单能打开这份记录
- [x] `bash scripts/test.sh`

## 验收

菜单能打开记录。扫一遍、打几个字，记录里能对上扫和筛，并带耗时。测试不往用户日志目录写。
