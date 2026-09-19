# jhqs

A Quickshell desktop shell (bar, panels, notifications, lockscreen, theming).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/corzyy/jhqs/main/install.sh | bash
```

The installer clones the repo to `~/.config/quickshell/jhqs`, keeps any existing
`config/` and `themes/snapshots/`, and starts the shell. Options:

```sh
curl -fsSL https://raw.githubusercontent.com/corzyy/jhqs/main/install.sh | bash -s -- --no-start
```

| Flag / Env        | Description                                        |
| ----------------- | -------------------------------------------------- |
| `-y, --yes`       | Non-interactive                                    |
| `--no-start`      | Install only, don't start the shell                |
| `JHQS_REF`        | Branch/tag to install (default: `main`)            |
| `JHQS_DEST`       | Install directory (default: `~/.config/quickshell/jhqs`) |
| `JHQS_REPO`       | Git remote to install from                         |

## Update

```sh
~/.config/quickshell/jhqs/scripts/update-shell.sh
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the code layout.
