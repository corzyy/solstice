# solstice

A Quickshell desktop shell (bar, panels, notifications, lockscreen, theming).

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/corzyy/solstice/main/install.sh | bash
```

The installer clones the repo to `~/.config/quickshell/solstice`, keeps any existing
`config/` and `themes/snapshots/`, and starts the shell. Options:

```sh
curl -fsSL https://raw.githubusercontent.com/corzyy/solstice/main/install.sh | bash -s -- --no-start
```

| Flag / Env        | Description                                        |
| ----------------- | -------------------------------------------------- |
| `-y, --yes`       | Non-interactive                                    |
| `--no-start`      | Install only, don't start the shell                |
| `SOLSTICE_REF`        | Branch/tag to install (default: `main`)            |
| `SOLSTICE_DEST`       | Install directory (default: `~/.config/quickshell/solstice`) |
| `SOLSTICE_REPO`       | Git remote to install from                         |

## Update

```sh
~/.config/quickshell/solstice/scripts/update-shell.sh
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the code layout.
