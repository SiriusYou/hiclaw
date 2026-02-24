#!/bin/bash
# Setup host symlinks for AI coding CLI tool credentials
# Runs at container startup (supervisord priority=750)
# Only symlinks config directories (credentials); binaries are installed in the container

set -e

for config_dir in .claude .gemini .qoder; do
    host_dir="/host-share/$config_dir"
    container_dir="/root/$config_dir"
    if [ -d "$host_dir" ]; then
        if [ -L "$container_dir" ]; then
            echo "[setup-host-symlinks] ~/$config_dir already symlinked, skipping"
        else
            rm -rf "$container_dir" 2>/dev/null || true
            ln -sf "$host_dir" "$container_dir"
            echo "[setup-host-symlinks] Linked ~/$config_dir -> /host-share/$config_dir"
        fi
    else
        echo "[setup-host-symlinks] /host-share/$config_dir not found, skipping"
    fi
done

echo "[setup-host-symlinks] Done"
