# istoreos-app-hub

面向 iStoreOS/OpenWrt 插件开发的聚合式仓库。

核心目标：把同一个插件分散在不同 legacy 仓库中的源码与描述文件聚合到同一目录，降低跨仓理解成本，让人和 AI 都能在单一上下文内完成分析、改造和同步发布。

## 项目定位

传统结构按“类型”拆分（services 仓、luci 仓、meta 仓），导致同一插件分散在多个位置。

本仓库按“插件”聚合（目录名保持 legacy 包名，不改名）：

- 一个插件一个目录
- 插件目录下直接放 legacy 包目录（例如：`<app>`、`luci-app-<app>`、`app-meta-<app>`）
- 通过 rsync 脚本与历史仓双向同步

## 仓库结构

```text
istoreos-app-hub/
├── apps/
│   └── <app-name>/
│       ├── <services-pkg>/
│       ├── <luci-pkg>/
│       └── <meta-pkg>/
├── docs/
└── README.md
```

说明：

- `apps/<app-name>/` 是插件聚合根目录。
- 目录下放“包目录”，且目录名与 legacy 侧保持一致（同步时不会改名）。
- 新插件初始化模板见：`docs/app-template.md`。

## Legacy 映射（推荐）

推荐使用 Go 工具 `syncapps` + `syncapps.yaml` 做显式映射（每个 app 可配置不同来源与目标）。
详见：`docs/syncapps.md`。

## 同步脚本

同步使用 Go 工具 `syncapps` + `syncapps.yaml`（支持自动扫描生成映射、全量/单 app 同步、dry-run）。

详见：`docs/syncapps.md`。

### 常用命令

```bash
# 自动扫描 legacy 并生成/补全映射
make syncapps-autogen

# 预演全量同步（不写入）
make syncapps-dry-all

# 执行全量同步
make syncapps-all

# 同步单个 app（可加 DRY=1 / DIRECTION=push|pull）
make syncapps-app APP=istorepanel
```

## AI 快速上下文（重点）

给 AI 协作时，请优先告知以下信息：

- 本仓库是“按插件聚合”，不是按类型拆分。
- 任何功能修改，优先在 `apps/<app-name>/` 内完成。
- 同步使用 `syncapps.yaml` + `make syncapps-*`，先用 `--dry-run`/`DRY=1` 预演。

建议给 AI 的任务模板：

```text
请在 apps/<app-name>/ 下修改，保持 services/luci/meta 聚合结构。
完成后给出 dry-run 同步命令，并说明会影响哪些 legacy 目录。
```

## 推荐工作流

1. 在 `apps/<app-name>/` 内开发和联调。
2. 提交前先执行 `--dry-run`，确认同步变更范围。
3. 执行正式同步（默认不传播删除；需要时显式加 `DELETE=1`）。
4. 到 legacy 仓执行各自的构建/发布流程。

## 约定与边界

- 目录命名建议与历史包名保持一致，减少映射歧义。
- 新增插件时先创建骨架：`apps/<app>/services`、`apps/<app>/luci`、`apps/<app>/meta`。
- 推荐把 `syncapps.yaml` 纳入版本控制，作为团队的映射共识。

## 下一步建议

- 增加 `scripts/check-diff.sh`：检查 hub 与 legacy 是否一致。
- 在 CI 增加 dry-run + 变更清单校验，避免误同步。
