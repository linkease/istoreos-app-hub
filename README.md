# istoreos-app-hub

面向 iStoreOS/OpenWrt 插件开发的聚合式仓库。

核心目标：把同一个插件分散在不同 legacy 仓库中的源码与描述文件聚合到同一目录，降低跨仓理解成本，让人和 AI 都能在单一上下文内完成分析、改造和同步发布。

## 项目定位

传统结构按“类型”拆分（services 仓、luci 仓、meta 仓），导致同一插件分散在多个位置。

本仓库按“插件”聚合（目录名保持 legacy 包名，不改名）：

- 一个插件一个目录
- 插件目录下直接放 legacy 包目录（例如：`<app>`、`luci-app-<app>`、`app-meta-<app>`）
- 通过 Go 工具 `syncapps` 与 legacy 目录双向同步（底层 rsync）

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

## 同步

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

## 远程快速部署（联调）

用于把 `apps/<id>/` 下“依赖少、路径规律明显”的代码快速覆盖到目标测试路由器，方便调试（不负责部署/解压预编译二进制）。

1) 在 `.it-runner/.env.local` 配置目标机（此文件被 `.gitignore` 忽略）：

```bash
DEPLOY_HOST=192.168.1.1
DEPLOY_USER=root
DEPLOY_PORT=22
DEPLOY_SINGLE_APP=kai
```

2) 运行：

```bash
# 先看会覆盖哪些文件
make deploy-app-dry APP=kai

# 执行部署（默认会在远端 /tmp 下做一次备份）
make deploy-app APP=kai
```

常用可选环境变量：

- `DEPLOY_BACKUP=0`：不备份直接覆盖（更快，但不安全）
- `DEPLOY_RESTART=1` + `DEPLOY_SERVICES="kai"`：部署后重启指定 init.d 服务
- `DEPLOY_RESTART_UHTTPD=1`：部署后 reload/restart `uhttpd`（LuCI 变更偶尔需要）
- `DEPLOY_CHECK_LUCI_COMPAT=0`：禁用 Lua LuCI 依赖检查（默认会在目标机缺少 `luci-compat` 时拒绝部署 Lua 控制器/模型文件，避免把 LuCI 部署“部署崩”）
- `DEPLOY_CHECK_UBUS=0`：禁用 ubus 可用性检查（默认在目标机 ubus 不可用时拒绝部署 Lua LuCI 文件）

实现见：`tools/deploy-to-remote.sh`（支持从 LuCI 目录、Makefile 里的 `./files -> $(1)/...` 映射、以及 `root/`/嵌套 `files/` overlay 收集待部署文件）。

## AI 快速上下文（重点）

给 AI 协作时，请优先告知以下信息：

- 本仓库是“按插件聚合”，不是按类型拆分。
- 任何功能修改，优先在 `apps/<app-name>/` 内完成。
- 同步使用 `syncapps.yaml` + `make syncapps-*`，先用 `--dry-run`/`DRY=1` 预演。
- 需要 AI 快速知道“仓库里有哪些软件”：先运行 `make apps-catalog` 生成 `docs/apps-catalog.min.md`，并在对话开头引用它（模板见 `docs/ai-prompt.md`）。

建议给 AI 的任务模板：

```text
请在 apps/<app-name>/ 下修改，保持“包目录名与 legacy 一致、不改名”的聚合结构（例如 luci-app-*/app-meta-*）。
完成后给出 dry-run 同步命令，并说明会影响哪些 legacy 目录。
```

## 推荐工作流

1. 在 `apps/<app-name>/` 内开发和联调。
2. 提交前先执行 `--dry-run`，确认同步变更范围。
3. 执行正式同步（默认不传播删除；需要时显式加 `DELETE=1`）。
4. 到 legacy 仓执行各自的构建/发布流程。

## 约定与边界

- 目录命名建议与历史包名保持一致，减少映射歧义。
- 新增插件时先创建 `apps/<app>/`，并在其下按需创建包目录（例如 `<app>`、`luci-app-<app>`、`app-meta-<app>`）。
- 推荐把 `syncapps.yaml` 纳入版本控制，作为团队的映射共识。

## 下一步建议

- 增加 “Strict 模式”（状态文件/冲突检测/删除传播策略）。
- 在 CI 增加 dry-run + 变更清单校验，避免误同步。
