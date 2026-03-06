# App Template

本文件定义 `istoreos-app-hub` 中“新插件”的标准骨架、命名规范与最小流程，供人和 AI 统一执行。

## 1. 目录骨架

新插件统一放在：`apps/<app-name>/`

```text
apps/<app-name>/
├── <services-pkg>/   # e.g. <app> or other service pkg name
├── <luci-pkg>/       # e.g. luci-app-<app>
└── <meta-pkg>/       # e.g. app-meta-<app>
```

说明：

- `apps/<app-name>/` 下直接放“包目录”，目录名保持与 legacy 一致（例如 `luci-app-*`、`app-meta-*`），同步时不会改名。

## 2. 命名建议

- `app-name`：建议使用业务语义名，短横线风格，例如 `app-foo`。
- `service-pkg`：尽量与 legacy 目标目录名一致。
- `luci-pkg`：通常为 `luci-app-*` 或 `luci-lib-*`。
- `meta-pkg`：通常为 `app-meta-*`。

原则：尽量沿用历史包名，减少映射歧义和重复目录。

## 3. 快速初始化

```bash
APP=app-foo
mkdir -p apps/${APP}

# 下面是示例包名，按实际项目替换
mkdir -p apps/${APP}/foo-service
mkdir -p apps/${APP}/luci-app-foo
mkdir -p apps/${APP}/app-meta-foo
```

## 4. 同步流程

### 生成映射与同步（推荐）

```bash
# 自动扫描 legacy 并生成/补全 syncapps.yaml
make syncapps-autogen

# 预演（不写入）
LEGACY_ROOT=/path/to/openwrt-apps make syncapps-app APP=app-foo DRY=1

# 正式同步
LEGACY_ROOT=/path/to/openwrt-apps make syncapps-app APP=app-foo
```

## 5. 提交前检查清单

- `apps/<app-name>/services|luci|meta` 结构完整。
- 包目录命名与 legacy 保持一致。
- 已执行 `DRY=1` 预演，确认影响范围符合预期。
- 确认是否需要 `DELETE=1`（传播删除，危险）。

## 6. AI 协作模板

可直接把以下文本给 AI：

```text
请在 apps/<app-name>/ 内修改，保持“包目录名与 legacy 一致、不改名”的聚合结构（例如 luci-app-*/app-meta-*）。
修改后给出：
1) `make syncapps-app APP=<app-name> DRY=1` 的输出摘要
2) 实际会影响的 legacy 目录列表
3) 是否需要 `DELETE=1` 的建议
```
