# it-runner

This directory defines runnable tasks for the it-runner web UI.

## Files

- `.it-runner/project.yaml`: Project entry (tasks/logs/cache dirs, env files)
- `.it-runner/envs/000-defaults.env`: Default non-secret env (committable)
- `.it-runner/envs/010-local.env`: Local overrides for this workspace
- `.it-runner/env-templates/080-secret-local.env.example`: Example secrets file (committable)
- `.it-runner/tasks/`: Task definitions (directory layout)

## Environment variables

- `PROJECT_ROOT`: Provided by it-runner at runtime.
- `LEGACY_ROOT`: Legacy repos root (used by `syncapps.yaml:legacy_root` if you choose to reference it).
- `DATA_ROOT`: External data root (for logs/cache if you choose to configure it).
- `APP`: App id (e.g. `openclaw`) used by deploy/sync tasks.

## Task-centric patterns in this repo

- `deploy-app` / `deploy-single-app`
  - default selectors: `.it-runner/tasks/<task>/envs/000-defaults.env`
  - deploy target: `.it-runner/envsets/deploy-targets/<target>/000-base.env`
  - app/runtime profile: `.it-runner/envsets/task-runtimes/<task>/<profile>/000-base.env`
- `syncapps-app`
  - default selector: `.it-runner/tasks/syncapps-app/envs/000-defaults.env`
  - runtime profile: `.it-runner/envsets/task-runtimes/syncapps-app/<profile>/000-base.env`

## Task layout

This repo uses the recommended directory layout:

` .it-runner/tasks/<task>/task.yaml `

Directories starting with `_` (like `.it-runner/tasks/_includes/`) are ignored by it-runner.

## Adding a task

Minimal fields:

```yaml
name: "my-task"
version: "1"
workspace:
  workdir: "."
run:
  cmds:
    - "make my-target"
```

For this repo, tasks intentionally call `make <target>` to reuse the project’s Makefile entry points.

## Deploy workflow (recommended)

- Set `.it-runner/envs/010-local.env`, for example:
  - `APP=openclaw`
  - `DEPLOY_HOST=192.168.1.1` `DEPLOY_USER=root` `DEPLOY_PORT=22`
- Run task `deploy-current-app` (or `deploy-current-app-dry` to preview payload).

## OpenClawMgr remote install (debug)

- Ensure `.it-runner/envs/010-local.env` contains `DEPLOY_HOST/DEPLOY_USER/DEPLOY_PORT`
- Run task `openclawmgr-install`
  - It runs `/usr/libexec/istorec/openclawmgr.sh install` on the remote box via SSH (prefer taskd if present)
  - Logs are saved under `.it-runner/logs/openclawmgr-install/`
