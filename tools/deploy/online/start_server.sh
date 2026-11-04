#!/bin/sh
set -eu
# The systemd unit sets both directories explicitly; overrides are useful for a local bundle check.
task_server_root=${ORBSTRIKE_SERVER_ROOT:-${SFERY_SERVER_ROOT:-/opt/orbstrike-online/current}}
task_godot_bin=${GODOT:-/opt/orbstrike-online/godot}
task_state_dir=${ORBSTRIKE_STATE_DIR:-${SFERY_STATE_DIR:-/var/lib/orbstrike-online}}
task_port=${ORBSTRIKE_PORT:-${SFERY_PORT:-8910}}
mkdir -p "$task_state_dir"
export XDG_DATA_HOME="$task_state_dir/data"
export XDG_CONFIG_HOME="$task_state_dir/config"
export XDG_CACHE_HOME="$task_state_dir/cache"
exec "$task_godot_bin" --headless --path "$task_server_root" --log-file "$task_state_dir/server.log" \
    -s res://network/server_main.gd -- "--port=$task_port" --bind=127.0.0.1
