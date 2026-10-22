#!/usr/bin/env bash
# Joining a running game, getting your crew back (also when the old connection never closed),
# and ending the game, against a local dedicated server.
# Usage: tests/net_room_test.sh [godot binary]
set -u
GODOT=${1:-godot}
cd "$(dirname "$0")/.."
PORT=7792
run() { $GODOT --headless --path . "$@"; }
client() { run --script res://tests/net_room_client.gd -- --port=$PORT "$@"; }

run -- --server --port=$PORT > "${SERVER_LOG:-/dev/null}" 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null; pkill -f "[-]-server --port=$PORT"' EXIT
sleep 3
client --role=host --token=host-device &
HOST=$!
sleep 4
client --role=late --token=phone-1
LATE=$?
sleep 2
client --role=ghost --token=phone-2 &
GHOST=$!
sleep 4
client --role=back --token=phone-2
BACK=$?
wait $GHOST
GHOSTRC=$?
wait $HOST
HOSTRC=$?
if [ $LATE -eq 0 ] && [ $BACK -eq 0 ] && [ $GHOSTRC -eq 0 ] && [ $HOSTRC -eq 0 ]; then echo "net room: ok"; else echo "net room: FAILED"; exit 1; fi
