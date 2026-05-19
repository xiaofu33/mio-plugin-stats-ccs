# MioIsland 统计插件

[![Plugin](https://img.shields.io/badge/MioIsland-plugin-CAFF00?style=flat-square)](https://github.com/MioMioOS/MioIsland)
[![macOS](https://img.shields.io/badge/macOS-15%2B-black?style=flat-square&logo=apple)](https://github.com/MioMioOS/MioIsland)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

一个报纸风格的 Claude Code 使用统计插件，为 [MioIsland](https://github.com/MioMioOS/MioIsland) 提供每日和每周的 API Token 消耗与费用展示。

通过读取 `~/.cc-switch/cc-switch.db`（SQLite），聚合 `proxy_request_logs` 中的请求记录，计算 Token 用量、缓存效率、模型费用等指标。

## 功能

- **报纸排版布局** — 报头、衬线斜体标题、两栏正文、细线分隔。纯文字排版，无图表。
- **日 / 周视图切换** — 支持查看今天或本周的数据，两种模式各有独立的分析视角。
- **Token 与费用追踪** — 输入/输出 Token 数、缓存读取率、每日/每周 API 总花费。
- **按模型细分** — 查看各模型的 Token 用量和费用分布。
- **周一起始** — 本周数据从周一开始计算，符合日历周习惯。
- **智能洞察** — 自动识别高流量日、高成本模型、优秀缓存效率、连续活跃里程碑。
- **双语支持** — 跟随 MioIsland 的 `appLanguage` 设置（中文/英文/自动）。

## 数据来源

本插件从 [cc-switch](https://github.com/xiaofu33/cc-switch) 的 SQLite 数据库中读取数据：

```
~/.cc-switch/cc-switch.db → proxy_request_logs 表
```

数据包含每次 API 请求的时间戳、模型名称、输入/输出 Token 数、缓存命中 Token 数、费用等信息。

## 构建与安装

```bash
# 仅构建
./build.sh

# 构建并安装到 MioIsland 插件目录
./build.sh install
```

安装后重启 MioIsland 即可加载新版本。

输出路径：
- 构建产物：`build/stats.bundle`
- 安装目标：`~/.config/codeisland/plugins/stats.bundle`

## 工作原理

1. `AnalyticsCollector` 每日通过系统 `sqlite3 -json` 命令行查询 `proxy_request_logs` 表
2. 聚合数据按周一至周日切分为本周和上周
3. 结果序列化缓存到 `~/Library/Application Support/CodeIsland/analytics_cache.json`，下次启动秒开
4. `EditorsNoteService` 调用本地安装的 `claude` CLI 生成每日/每周编辑寄语（不含源码，仅使用汇总数据）
5. 寄语结果按日期和语言缓存，避免重复消耗 API 额度

## 技术细节

- 使用 Swift `Process` + `/usr/bin/sqlite3 -json` 执行查询，无需链接 libsqlite3
- 插件格式为 macOS `.bundle`，编译为动态库由 MioIsland 运行时加载
- 目标架构：`arm64-apple-macos15.0`
- 支持 ad-hoc 代码签名

## 依赖

- macOS 15+
- MioIsland v2.0+
- cc-switch（用于提供代理日志数据）

## License

MIT.
