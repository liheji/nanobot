#!/bin/sh
dir="$HOME/.nanobot"

# Render deploy path (see render.yaml + render-config.json). Gated on Render's
# automatic RENDER=true env var so local Docker/podman usage is unaffected.
# Initializes the on-disk config from the committed template (wiring secrets via
# ${VAR} env vars, keeping runtime data on the persistent disk) and appends the
# --config flag. Logs each decision so a failed start is diagnosable in Render's
# logs.
if [ "$RENDER" = "true" ]; then
    echo "[entrypoint] Render deploy — starting as $(id)"
    mkdir -p "$dir" || echo "[entrypoint] warning: mkdir $dir failed"
    config="$dir/config.json"
    # Initialize config only when it does not already exist, so WebUI/provider
    # settings edited at runtime survive restarts. The disk persists config.json
    # across deploys; overwriting it every boot would discard those changes.
    if [ ! -f "$config" ]; then
        echo "[entrypoint] initializing $config from render-config.json"
        cp /app/render-config.json "$config" || echo "[entrypoint] warning: cp config failed"
    else
        echo "[entrypoint] existing $config found — leaving it in place"
    fi
    set -- "$@" --config "$config"
fi

# Running as root — ensure the data dir exists and is writable.
if [ "$(id -u)" = "0" ]; then
    mkdir -p "$dir" 2>/dev/null || echo "[entrypoint] warning: mkdir $dir failed"
fi

# CLI Apps survive on the persistent volume (installed.json, skills), but the
# installed binaries do not: pip installs land in /app/.venv and npm -g / uv
# tool installs in image layers, all wiped when the container is recreated, so
# every recorded app would show up as "missing" after an upgrade. Reinstall
# them through nanobot's own installer: it skips apps whose entry point is
# already on PATH and reinstalls the rest via their recorded strategy (pip,
# npm, uv; bundled apps only need the image itself). Per-app failures are
# logged and skipped — a failed restore must never block the gateway.
if [ -f "$dir/cli-apps/installed.json" ]; then
    python3 - <<'PYEOF'
import sys
import traceback

try:
    from nanobot.apps.cli.service import CliAppManager
    from nanobot.config.paths import get_workspace_path

    manager = CliAppManager(workspace=get_workspace_path())
    names = manager.installed_names()
except Exception:
    print("[entrypoint] CLI apps restore skipped:", file=sys.stderr)
    traceback.print_exc()
    sys.exit(0)

if not names:
    print("[entrypoint] CLI apps restore: no apps recorded")
    sys.exit(0)

print(f"[entrypoint] CLI apps restore: {len(names)} recorded: {', '.join(names)}")
for name in names:
    try:
        manager.install(name)
        print(f"[entrypoint] CLI apps restore: {name} ok")
    except Exception as exc:
        print(f"[entrypoint] CLI apps restore: {name} failed: {exc}", file=sys.stderr)
PYEOF
else
    echo "[entrypoint] no cli-apps/installed.json — no CLI apps to restore"
fi

exec nanobot "$@"
