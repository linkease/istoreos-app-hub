# istoreos-app-hub

面向 iStoreOS/OpenWrt 插件开发的聚合式仓库。

核心目标：把同一个插件的 `services / luci / meta` 聚合到同一目录，降低跨仓理解成本，让人和 AI 都能在单一上下文内完成分析、改造和同步发布。

## 项目定位

传统结构按“类型”拆分（services 仓、luci 仓、meta 仓），导致同一插件分散在多个位置。

本仓库按“插件”聚合：

- 一个插件一个目录
- 插件内固定三层：`services/`、`luci/`、`meta/`
- 通过 rsync 脚本与历史仓双向同步

## 仓库结构

```text
istoreos-app-hub/
├── apps/
│   └── <app-name>/
│       ├── services/
│       ├── luci/
│       └── meta/
├── scripts/
│   ├── sync-to-legacy.sh
│   └── sync-from-legacy.sh
├── docs/
└── README.md
```

说明：

- `apps/<app-name>/` 是插件聚合根目录。
- `services/`、`luci/`、`meta/` 下建议直接放具体包目录（可多个）。
- `scripts/` 存放与历史仓互通的同步脚本。
- 新插件初始化模板见：`docs/app-template.md`。

## Legacy 映射（当前默认）

`scripts/sync-to-legacy.sh` 与 `scripts/sync-from-legacy.sh` 默认映射如下：

- `apps/<app>/services/*` <-> `../istore/luci/*`
- `apps/<app>/luci/*` <-> `../nas-packages-luci/luci/*`
- `apps/<app>/meta/*` <-> `../openwrt-app-meta/applications/*`

注意：这里的同步粒度是“包目录”（`*`），不是整个 `<app>` 目录直接一一映射。

## 同步脚本

### 1) hub -> legacy

```bash
# 同步单个插件
scripts/sync-to-legacy.sh --app app-foo

# 同步全部插件
scripts/sync-to-legacy.sh --all

# 预演（不写入）
scripts/sync-to-legacy.sh --all --dry-run
```

### 2) legacy -> hub

```bash
# 回灌单个插件
scripts/sync-from-legacy.sh --app app-foo

# 回灌全部插件
scripts/sync-from-legacy.sh --all

# 预演（不写入）
scripts/sync-from-legacy.sh --all --dry-run
```

### 常用参数

- `--no-delete`：禁用 `rsync --delete`（更保守）
- `--apps-dir`：自定义 apps 根目录
- `--services-dir` / `--luci-dir` / `--meta-dir`：覆盖默认 legacy 路径

## AI 快速上下文（重点）

给 AI 协作时，请优先告知以下信息：

- 本仓库是“按插件聚合”，不是按类型拆分。
- 任何功能修改，优先在 `apps/<app-name>/` 内完成。
- 发布前走 `sync-to-legacy.sh`，必要时用 `--dry-run` 先检查。
- 如果要从旧仓补录，走 `sync-from-legacy.sh`。
- 同步单位是“包目录”，不是简单复制整个 app 根目录。

建议给 AI 的任务模板：

```text
请在 apps/<app-name>/ 下修改，保持 services/luci/meta 聚合结构。
完成后给出 dry-run 同步命令，并说明会影响哪些 legacy 目录。
```

## 推荐工作流

1. 在 `apps/<app-name>/` 内开发和联调。
2. 提交前先执行 `--dry-run`，确认同步变更范围。
3. 执行正式同步（默认带 `--delete`，请谨慎）。
4. 到 legacy 仓执行各自的构建/发布流程。

## 约定与边界

- 目录命名建议与历史包名保持一致，减少映射歧义。
- 新增插件时先创建骨架：`apps/<app>/services`、`apps/<app>/luci`、`apps/<app>/meta`。
- `sync-from-legacy.sh` 会基于 hub 已存在的包目录进行回灌映射，不会盲目全量导入整个 legacy 仓。

## 下一步建议

- 增加 `scripts/check-diff.sh`：检查 hub 与 legacy 是否一致。
- 在 CI 增加 dry-run + 变更清单校验，避免误同步。
