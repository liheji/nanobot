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

exec nanobot "$@"
