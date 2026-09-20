#!/usr/bin/env bash
# matugen-run.sh — matugen wrapper that respects solstice Application Theming toggles.
# Ported from DMS `dms matugen queue` template-skip logic (runUserTemplates /
# runDmsTemplates + per-template bools), adapted to plain matugen.
#
# Speed design (wallpaper path is latency-critical, ~0.2s core vs ~3s papirus):
#   1. builds a filtered copy of ~/.config/matugen/config.toml with mktemp
#      (drops disabled template blocks; drops unknown user blocks when
#      runUserTemplates=false; never drops quickshell/umbriel core blocks)
#   2. runs ONE synchronous `matugen -c <filtered> "$@"` WITHOUT the papirus
#      block (papirus icon regeneration is ~90% of the runtime) so the shell
#      recolors in ~0.3-0.5s.
#   3. replays the papirus block (and the terminals-always-dark kitty block,
#      if needed) in detached background jobs that never hold the caller's
#      stdout pipe — icons/terminals catch up a few seconds later.
set -u

SRC_CFG="$HOME/.config/matugen/config.toml"
THEMING_JSON="$HOME/.config/quickshell/solstice/config/theming_settings.json"

MATUGEN_BIN="matugen"
[ -x "$HOME/.cargo/bin/matugen" ] && MATUGEN_BIN="$HOME/.cargo/bin/matugen"
if ! command -v "$MATUGEN_BIN" >/dev/null 2>&1 && [ ! -x "$MATUGEN_BIN" ]; then
  echo "[matugen-run] matugen binary not found" >&2
  exit 127
fi
if [ ! -f "$SRC_CFG" ]; then
  echo "[matugen-run] missing $SRC_CFG, aborting (no stale config run)" >&2
  exit 2
fi

SYNC_CFG="$(mktemp /tmp/solstice-matugen-sync.XXXXXX.toml)"
PAPIRUS_CFG="$(mktemp /tmp/solstice-matugen-papirus.XXXXXX.toml)"
KITTY_CFG="$(mktemp /tmp/solstice-matugen-kitty.XXXXXX.toml)"

# Detect requested mode from CLI (ThemeEngine always passes -m <mode>).
MODE_IS_LIGHT=false
for a in "$@"; do
  [ "$a" = "light" ] && MODE_IS_LIGHT=true
done
# Only the `image` flow benefits from papirus deferral; color/json imports
# are one-shot and rare, run them synchronously as before.
WANT_DEFER=false
[ "${1:-}" = "image" ] && WANT_DEFER=true

# Single python pass: write sync/papirus/kitty configs, report flags.
# shellcheck disable=SC2086
EVAL_OUT="$(MODE_LIGHT="$MODE_IS_LIGHT" WANT_DEFER="$WANT_DEFER" python3 - "$SRC_CFG" "$THEMING_JSON" "$SYNC_CFG" "$PAPIRUS_CFG" "$KITTY_CFG" <<'EOF'
import json, os, re, sys
src, theming_path, sync_out, papirus_out, kitty_out = sys.argv[1:6]
try:
    cfg = open(src).read()
except OSError:
    sys.exit(2)
try:
    t = json.loads(open(theming_path).read())
except Exception:
    t = {}

def off(key):
    return t.get(key) is False

drop = set()
if off("templateGtk3"): drop.add("gtk3")
if off("templateGtk4"): drop.add("gtk4")
if off("templateQt5ct"): drop.add("qt5ct")
if off("templateQt6ct"): drop.add("qt6ct")
if off("templateQtColorscheme"): drop.add("qt-colorscheme")
if off("templateKitty"): drop.add("kitty")
if off("templateGhostty"): drop.add("ghostty")
if off("templateFcitx5"): drop.add("fcitx5")
if off("templateFirefox"): drop.add("firefox")
if off("templateVscode"): drop.update(["vscode-raw", "vscode-json"])
if off("templateNeovim"): drop.add("neovim")
if off("templateBtop"): drop.add("btop")
if off("templateVesktop"): drop.update(["vesktop-midnight", "vesktop-system24"])
if off("templateObs"): drop.update(["obs", "obs-native"])
if off("templateOpencode"): drop.add("opencode")
if off("templatePapirus"): drop.add("papirus")
if off("templatePrismlauncher"): drop.add("prismlauncher")

known = {"quickshell", "umbriel", "gtk3", "gtk4", "qt5ct", "qt6ct",
         "qt-colorscheme", "kitty", "ghostty", "fcitx5", "firefox",
         "vscode-raw", "vscode-json", "neovim", "btop", "vesktop-midnight",
         "vesktop-system24", "obs", "obs-native", "opencode", "papirus",
         "prismlauncher"}
run_user = t.get("runUserTemplates", True) is not False

def split_blocks(text):
    """Split config into (head, [(id, block_text)]) preserving order."""
    head_parts, blocks = [], []
    cur_id, cur = None, []
    for line in text.splitlines(keepends=True):
        m = re.match(r"\[templates\.([^\]]+)\]", line.strip())
        if m:
            if cur_id is not None:
                blocks.append((cur_id, "".join(cur)))
            elif cur:
                head_parts.append("".join(cur))
            cur_id, cur = m.group(1), [line]
        elif cur_id is not None:
            if line.startswith("[") and not line.startswith("[templates."):
                blocks.append((cur_id, "".join(cur)))
                cur_id, cur = None, [line]
            else:
                cur.append(line)
        else:
            head_parts.append(line)
    if cur_id is not None:
        blocks.append((cur_id, "".join(cur)))
    elif cur:
        head_parts.append("".join(cur))
    return "".join(head_parts), blocks

head, blocks = split_blocks(cfg)
kept = [(i, b) for (i, b) in blocks
        if i not in drop and (i in known or run_user)]

papirus_blocks = [(i, b) for (i, b) in kept if i == "papirus"]
kitty_blocks = [(i, b) for (i, b) in kept if i == "kitty"]

# Defer papirus to background only when it is enabled and present.
defer = (os.environ.get("WANT_DEFER") == "true" and len(papirus_blocks) > 0)
sync_blocks = [(i, b) for (i, b) in kept if not (defer and i == "papirus")]
open(sync_out, "w").write(head + "".join(b for _, b in sync_blocks))

have_papirus, have_kitty = False, False
if defer:
    open(papirus_out, "w").write(head + "".join(b for _, b in papirus_blocks))
    have_papirus = True

# Terminals-always-dark (DMS parity): light shell, dark terminals.
want_dark = t.get("terminalsAlwaysDark") is True
kitty_on = t.get("templateKitty", True) is not False
if os.environ.get("MODE_LIGHT") == "true" and want_dark and kitty_on and kitty_blocks:
    open(kitty_out, "w").write(head + "".join(b for _, b in kitty_blocks))
    have_kitty = True

print("drop=" + ",".join(sorted(drop)) if drop else "drop=")
print("defer_papirus=1" if have_papirus else "defer_papirus=0")
print("kitty_dark=1" if have_kitty else "kitty_dark=0")
EOF
)"
PY_CODE=$?
if [ $PY_CODE -ne 0 ]; then
  echo "[matugen-run] config filter failed (code $PY_CODE)" >&2
  rm -f "$SYNC_CFG" "$PAPIRUS_CFG" "$KITTY_CFG"
  exit $PY_CODE
fi
FILTERED="$(echo "$EVAL_OUT" | grep '^drop=' || echo 'drop=')"
DEFER_PAPIRUS="$(echo "$EVAL_OUT" | grep '^defer_papirus=' | cut -d= -f2)"
KITTY_DARK="$(echo "$EVAL_OUT" | grep '^kitty_dark=' | cut -d= -f2)"
echo "[matugen-run] $FILTERED defer_papirus=${DEFER_PAPIRUS:-0} kitty_dark=${KITTY_DARK:-0}" | logger -t matugen-run 2>/dev/null || true

# Caller args minus any caller-supplied -c/--config (we supply our own).
CALL_ARGS=()
SKIP_NEXT=false
for a in "$@"; do
  if $SKIP_NEXT; then SKIP_NEXT=false; continue; fi
  case "$a" in
    -c|--config) SKIP_NEXT=true;;
    *) CALL_ARGS+=("$a");;
  esac
done

# Dark-mode variant of the caller args for the kitty-only replay:
# -m/--mode <v> -> -m dark, bare light|dark|smart -> dark.
dark_args() {
  local skip=false out=()
  local a
  for a in "$@"; do
    if $skip; then skip=false; continue; fi
    case "$a" in
      -m|--mode) out+=("$a" "dark"); skip=true;;
      -c|--config) skip=true;;
      light|dark|smart) out+=("dark");;
      *) out+=("$a");;
    esac
  done
  printf '%s\0' "${out[@]}"
}

"$MATUGEN_BIN" -c "$SYNC_CFG" "${CALL_ARGS[@]}"
CODE=$?
rm -f "$SYNC_CFG"

# Detached replays: redirect everything off the caller's stdout pipe so the
# foreground caller returns as soon as the fast sync run is done. Each job
# cleans up its own temp config.
if [ "${DEFER_PAPIRUS:-0}" = "1" ]; then
  ( "$MATUGEN_BIN" -c "$PAPIRUS_CFG" "${CALL_ARGS[@]}" 2>&1 | logger -t matugen-papirus 2>/dev/null; rm -f "$PAPIRUS_CFG" ) >/dev/null 2>&1 < /dev/null & disown || true
else
  rm -f "$PAPIRUS_CFG"
fi
if [ "${KITTY_DARK:-0}" = "1" ]; then
  mapfile -d '' -t DARK_ARGS < <(dark_args "${CALL_ARGS[@]}")
  ( "$MATUGEN_BIN" -c "$KITTY_CFG" "${DARK_ARGS[@]}" 2>&1 | logger -t matugen-terminals 2>/dev/null; rm -f "$KITTY_CFG" ) >/dev/null 2>&1 < /dev/null & disown || true
else
  rm -f "$KITTY_CFG"
fi

exit $CODE
