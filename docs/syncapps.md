# sync apps（双向同步规划与工具）

本仓库的目标是把同一个插件分散在不同 legacy 仓库中的源码与描述文件聚合到 `apps/<app>/` 下，并支持与 legacy 目录双向同步。

目前 legacy 根目录（本仓库的上一级）为：`/projects/workspace-linkease-ubuntu/openwrt-apps`，其中包含：

- `nas-packages`（常见 services 源码）
  - 例：`nas-packages/network/services/ddnsto`
- `nas-packages-luci`（常见 luci 源码）
  - 例：`nas-packages-luci/luci/luci-app-ddnsto`
- `openwrt-app-actions`（既有 luci 也有 services，目录结构按应用聚合）
  - 例：`openwrt-app-actions/applications/luci-app-istorepanel`
- `openwrt-app-meta`（最终描述文件 meta）
  - 例：`openwrt-app-meta/applications/app-meta-istorepanel`

## 需求拆解

1. 将“有源代码的 app”聚合到本仓库 `apps/` 下：`apps/<app>/` 下直接放 legacy 包目录（目录名保持一致，例如 `luci-app-*`、`app-meta-*`），同步时不改名。
2. 每个插件的同步目标不一致：同一类内容（services/luci/meta）可能来自不同 legacy 仓库与不同路径。
3. 需要按文件修改时间（mtime）做双向同步：
   - legacy 侧更新 → 回灌到 `apps/<app>/...`
   - hub 侧更新 → 推回到 legacy 目录
4. 支持全量同步与单 app 同步（底层用 rsync）。

## 实施方案（MVP：Simple 模式）

说明：`rsync` 不是严格意义的“双向同步”工具；MVP 采用“mtime 更新的一方赢”的策略实现近似双向：

- 对每个映射对执行两次 rsync：
  1) hub(local) → legacy(remote)：`rsync -a --update`
  2) legacy(remote) → hub(local)：`rsync -a --update`
- 默认不传播删除（更安全），避免误删对方目录。

该模式满足“根据文件修改时间双向同步”的基本诉求，但不解决“双方都改了同一文件”的冲突提示，也不自动做删除传播。

## 后续增强（Strict 模式，规划）

为每个映射对维护 `.sync-state/` 状态文件：

- 记录上次同步时间与文件指纹（mtime/size，可选 hash）
- 本次扫描两边变化并分类：
  - 仅一边变更：单向同步
  - 两边变更：标记冲突并输出报告（默认不覆盖）
  - 删除传播：仅在“状态确认 + 另一边未修改”的情况下传播删除

## 配置：`syncapps.yaml`

每个 app 可分别配置 `services/luci/meta` 的一个或多个“映射对”，从而实现“每个插件同步目标不一致”的需求（每个 slot 可以有多个 package 目录）。

约定：

- `local` 一般指向 `apps/<app>/<pkg-dir>`（例如 `apps/istorepanel/app-meta-istorepanel`）
- `remote` 指向 legacy 侧真实目录（例如 `openwrt-app-meta/applications/app-meta-istorepanel`）

### 关于 `legacy_root` / `LEGACY_ROOT` / `DATA_ROOT`

- `syncapps.yaml:legacy_root`：指向 legacy 仓库根目录（包含 `nas-packages`、`nas-packages-luci`、`openwrt-app-actions`、`openwrt-app-meta`），用于同步源码与 meta。
- `LEGACY_ROOT`：可选环境变量；仅当 `syncapps.yaml:legacy_root` 为空/未设置时作为回退来源。
- 优先级：若 `syncapps.yaml:legacy_root` 非空则优先生效；只有当其为空/未设置时才会回退使用环境变量 `LEGACY_ROOT`。
- `DATA_ROOT`：it-runner 用于放日志/缓存等运行数据的外部目录，和同步的 legacy 仓库根目录不是一回事。

注意：`syncapps` 不支持在 YAML 里写 `${VAR}` 这类环境变量展开；请用上述“空值回退”方式或直接写绝对路径。

配置文件位置：仓库根目录 `syncapps.yaml`（建议纳入版本控制，作为团队共识）。

## 工具：Golang 多命令布局

为便于 YAML 解析、状态管理与后续扩展，本仓库新增一个专门的 Go 代码目录：`tools/`。

- Go 模块：`tools/go.mod`
- 命令：`tools/cmd/syncapps`（MVP 实现 Simple 模式）

用法示例（推荐用 Makefile）：

```bash
# 自动扫描 legacy 并生成/补全映射
LEGACY_ROOT=/path/to/openwrt-apps make syncapps-autogen

# 预演：同步全部 app（双向，mtime 胜出，不落盘）
LEGACY_ROOT=/path/to/openwrt-apps make syncapps-dry-all

# 同步单个 app（只同步 meta slot）
LEGACY_ROOT=/path/to/openwrt-apps make syncapps-app APP=istorepanel SLOT=meta
```
