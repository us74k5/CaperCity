#!/usr/bin/env bash
# A networked player drops out, comes back, and plays a police fight through the real HUD.
# Usage: tests/net_fight_test.sh [godot binary] [--how=run] [--midfight] [--stall]
set -u
GODOT=${1:-godot}; shift
cd "$(dirname "$0")/.."
PORT=7794
run() { $GODOT --headless --path . "$@"; }

run -- --server --port=$PORT --test-hooks --stall-seconds=6 > "${SERVER_LOG:-/dev/null}" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; pkill -f "[-]-server --port=$PORT"; pkill -f "[n]et_fight_client.gd -- --role=partner"' EXIT
sleep 3
run --script res://tests/net_fight_client.gd -- --role=partner --port=$PORT --token=partner "$@" > "${PARTNER_LOG:-/dev/null}" 2>&1 &
sleep 2
run --script res://tests/net_fight_client.gd -- --role=player --port=$PORT --token=player "$@"
RC=$?
if [ $RC -eq 0 ]; then echo "net fight: ok"; else echo "net fight: FAILED"; exit 1; fi
