# it-runner

This directory defines runnable tasks for the it-runner web UI.

## Files

- `.it-runner/project.yaml`: Project entry (tasks/logs/cache dirs, env files)
- `.it-runner/envs/shared.env`: Default non-secret env (committable)
- `.it-runner/envs/secrets.env.example`: Example secrets file (committable)
- `.it-runner/tasks/`: Task definitions (directory layout)

## Environment variables

- `PROJECT_ROOT`: Provided by it-runner at runtime.
- `LEGACY_ROOT`: Legacy repos root (used by `syncapps.yaml:legacy_root` if you choose to reference it).
- `DATA_ROOT`: External data root (for logs/cache if you choose to configure it).
- `APP`: App id (e.g. `openclaw`) used by deploy/sync tasks.

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

- Set `.it-runner/.env.local` (ignored by git), for example:
  - `APP=openclaw`
  - `DEPLOY_HOST=192.168.1.1` `DEPLOY_USER=root` `DEPLOY_PORT=22`
- Run task `deploy-current-app` (or `deploy-current-app-dry` to preview payload).

## OpenClawMgr remote install (debug)

- Ensure `.it-runner/.env.local` contains `DEPLOY_HOST/DEPLOY_USER/DEPLOY_PORT`
- Run task `openclawmgr-install`
  - It runs `/usr/libexec/istorec/openclawmgr.sh install` on the remote box via SSH (prefer taskd if present)
  - Logs are saved under `.it-runner/logs/openclawmgr-install/`
