#!/bin/bash
# OpenClaw Zero Token 停止脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/.gateway-zero-token.pid"
PORT=3001

port_pid() {
  local port=$1
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti:"$port" 2>/dev/null
  elif command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | awk -v p="$port" '$4 ~ ":"p"$" {match($6,/pid=([0-9]+)/,a); if(a[1]) print a[1]}'
  fi
}

if [ -f "$PID_FILE" ]; then
  OLD_PID=$(cat "$PID_FILE")
  if kill -0 "$OLD_PID" 2>/dev/null; then
    echo "停止进程 (PID: $OLD_PID)..."
    kill "$OLD_PID" 2>/dev/null
    sleep 1
    if kill -0 "$OLD_PID" 2>/dev/null; then
      kill -9 "$OLD_PID" 2>/dev/null
    fi
  fi
  rm -f "$PID_FILE"
fi

PORT_PID=$(port_pid "$PORT")
if [ -n "$PORT_PID" ]; then
  echo "停止占用端口 $PORT 的进程 (PID: $PORT_PID)..."
  kill "$PORT_PID" 2>/dev/null
fi

echo "Gateway 已停止"
