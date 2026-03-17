# OpenClawMgr (openclawmgr)

## 交互/操作设计（草案）

目标：所有“长耗时/可失败”的操作都通过 `taskd` 运行，并在 LuCI 中弹出日志窗口（xterm），执行期间禁止并发启动其他任务。

### 操作分层

- **主流程（常用）**
  - `安装`：部署 Node + npm 安装 OpenClaw + 生成最小配置 + 启用并启动服务
  - `升级`：更新 OpenClaw（并重启服务）
  - `启动/重启/停止`：服务控制（必要时联动 enabled）
- **高级（危险/低频）**
  - `卸载`：移除运行时（保留数据目录）
  - `清理（含数据）`：移除运行时 + 删除数据目录

### 日志策略

- **任务日志（taskd）**：每次点击操作都创建/复用 `task_id=openclawmgr`，立即弹窗追踪 `/var/log/tasks/openclawmgr.log`。
- **安装器日志（installer.log）**：仍保留持久化日志 `${base_dir}/log/installer.log`；LuCI 可“一键查看”并在弹窗中展示（只读）。

### 并发控制

- LuCI 侧：操作按钮点击后立即禁用，直到 taskd 返回任务结束。
- 系统侧：依赖 `taskd` 自身锁机制（`/etc/init.d/tasks task_add ...` 返回非 0 表示已有任务在跑）。

### Save & Apply（配置应用）

- `Save & Apply` 不直接在 LuCI 进程内执行重启，而是通过 taskd 创建 `task_id=openclawmgr` 任务去执行：
  - `"/usr/libexec/istorec/openclawmgr.sh" restart`
- 页面加载时如检测到 `openclawmgr` 任务在运行，会自动弹出 taskd 日志窗口。

## 依赖

- `luci-lib-taskd`（含 `luci-lib-xterm` 与 `taskd`）
