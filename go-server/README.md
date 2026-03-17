# go-server

Simple Go HTTP server that exposes a file listing API and (optionally) serves the UI in `file-web/`.

## Run

From repo root:

```bash
go run ./go-server
```

## API

- `GET /api/files` -> `[]FileEntry`
  - optional `?hidden=1` to include dotfiles

By default it lists `go-server/files/`. Override with `-files` or `FILES_DIR`.

