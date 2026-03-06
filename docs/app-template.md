# App Template

本文件定义 `istoreos-app-hub` 中“新插件”的标准骨架、命名规范与最小流程，供人和 AI 统一执行。

## 1. 目录骨架

新插件统一放在：`apps/<app-name>/`

```text
apps/<app-name>/
├── services/
│   └── <service-pkg>/
├── luci/
│   └── <luci-pkg>/
└── meta/
    └── <meta-pkg>/
```

说明：

- 三个一级子目录固定为：`services`、`luci`、`meta`。
- 每个子目录下放“包目录”（可 0 个、1 个或多个）。
- 同步脚本按“包目录”粒度 rsync，不按 `<app-name>` 整体镜像。

## 2. 命名建议

- `app-name`：建议使用业务语义名，短横线风格，例如 `app-foo`。
- `service-pkg`：尽量与 legacy 目标目录名一致。
- `luci-pkg`：通常为 `luci-app-*` 或 `luci-lib-*`。
- `meta-pkg`：通常为 `app-meta-*`。

原则：尽量沿用历史包名，减少映射歧义和重复目录。

## 3. 快速初始化

```bash
APP=app-foo
mkdir -p apps/${APP}/{services,luci,meta}

# 下面是示例包名，按实际项目替换
mkdir -p apps/${APP}/services/foo-service
mkdir -p apps/${APP}/luci/luci-app-foo
mkdir -p apps/${APP}/meta/app-meta-foo
```

## 4. 同步流程

### hub -> legacy（发布主流程）

```bash
# 先预演
scripts/sync-to-legacy.sh --app app-foo --dry-run

# 再正式同步
scripts/sync-to-legacy.sh --app app-foo
```

### legacy -> hub（补录/回灌）

```bash
# 先预演
scripts/sync-from-legacy.sh --app app-foo --dry-run

# 再正式回灌
scripts/sync-from-legacy.sh --app app-foo
```

## 5. 提交前检查清单

- `apps/<app-name>/services|luci|meta` 结构完整。
- 包目录命名与 legacy 保持一致。
- 已执行 `--dry-run`，确认影响范围符合预期。
- 确认是否需要 `--no-delete`（保守模式）。

## 6. AI 协作模板

可直接把以下文本给 AI：

```text
请在 apps/<app-name>/ 内修改，保持 services/luci/meta 聚合结构。
修改后给出：
1) sync-to-legacy 的 dry-run 命令
2) 实际会影响的 legacy 目录列表
3) 是否需要 --no-delete 的建议
```
