#!/bin/bash
# OpenClaw Zero Token 启动脚本
# 参考 server.sh 编写

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_DIR="$SCRIPT_DIR/.openclaw"
CONFIG_FILE="$STATE_DIR/openclaw.json"
PID_FILE="$SCRIPT_DIR/.gateway-zero-token.pid"
PORT=3001

# ─── 辅助函数 ────────────────────────────────────────────────
port_pid() {
  local port=$1
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti:"$port" 2>/dev/null
  elif command -v ss >/dev/null 2>&1; then
    ss -tlnp 2>/dev/null | awk -v p="$port" '$4 ~ ":"p"$" {match($6,/pid=([0-9]+)/,a); if(a[1]) print a[1]}'
  fi
}

tmp_log() {
  if [ -d /tmp ]; then
    echo "/tmp/openclaw-zero-token-gateway.log"
  else
    echo "$SCRIPT_DIR/logs/openclaw-zero-token-gateway.log"
  fi
}

# ─── 初始化 ──────────────────────────────────────────────────
mkdir -p "$STATE_DIR"
mkdir -p "$SCRIPT_DIR/logs"

# 如果 .openclaw 目录不存在，从 upstream 复制一份
if [ ! -d "$STATE_DIR" ]; then
    cp -r "$SCRIPT_DIR/.openclaw-upstream-state" "$STATE_DIR"
    echo "已复制配置: .openclaw-upstream-state -> .openclaw"
fi

TMP_LOG=$(tmp_log)

# ─── 功能函数 ────────────────────────────────────────────────
stop_gateway() {
  if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
      echo "停止旧进程 (PID: $OLD_PID)..."
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
    sleep 1
  fi
}

start_gateway() {
  export OPENCLAW_STATE_DIR="$STATE_DIR"
  export OPENCLAW_GATEWAY_PORT="$PORT"

  # 读取 token
  GATEWAY_TOKEN=$(jq -r '.gateway.auth.token // empty' "$CONFIG_FILE" 2>/dev/null)

  echo "启动 OpenClaw Zero Token Gateway..."
  echo "状态目录: $OPENCLAW_STATE_DIR"
  echo "端口: $PORT"
  echo ""

  # 直接启动，不使用 wrapper
  nohup /usr/local/opt/node@22/bin/node "$SCRIPT_DIR/openclaw.mjs" gateway --port "$PORT" > "$TMP_LOG" 2>&1 &
  GATEWAY_PID=$!
  echo "$GATEWAY_PID" > "$PID_FILE"

  echo "等待 Gateway 就绪..."
  i=0
  while [ $i -lt 30 ]; do
    i=$((i + 1))
    if curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:$PORT/" 2>/dev/null; then
      echo "Gateway 已就绪 (${i}s)"
      break
    fi
    if ! kill -0 $GATEWAY_PID 2>/dev/null; then
      echo "Gateway 进程已退出，启动失败"
      cat "$TMP_LOG"
      rm -f "$PID_FILE"
      exit 1
    fi
    sleep 1
  done

  if kill -0 $GATEWAY_PID 2>/dev/null; then
    WEBUI_URL="http://127.0.0.1:$PORT/#token=${GATEWAY_TOKEN}"
    echo "Gateway 服务已启动 (PID: $GATEWAY_PID)"
    echo "Web UI: $WEBUI_URL"
    open "$WEBUI_URL" 2>/dev/null || echo "请手动在浏览器中打开: $WEBUI_URL"
  else
    echo "Gateway 服务启动失败，请查看日志:"
    cat "$TMP_LOG"
    rm -f "$PID_FILE"
    exit 1
  fi
}

# ─── 入口 ────────────────────────────────────────────────────
case "${1:-start}" in
  start)
    stop_gateway
    start_gateway
    ;;
  stop)
    stop_gateway
    echo "Gateway 服务已停止"
    ;;
  restart)
    stop_gateway
    start_gateway
    ;;
  status)
    if [ -f "$PID_FILE" ]; then
      PID=$(cat "$PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        GATEWAY_TOKEN=$(jq -r '.gateway.auth.token // empty' "$CONFIG_FILE" 2>/dev/null)
        echo "Gateway 服务运行中 (PID: $PID)"
        echo "Web UI: http://127.0.0.1:$PORT/#token=${GATEWAY_TOKEN}"
      else
        echo "Gateway 服务未运行 (PID 文件存在但进程已退出)"
      fi
    else
      PORT_PID=$(port_pid "$PORT")
      if [ -n "$PORT_PID" ]; then
        echo "端口 $PORT 被进程 $PORT_PID 占用"
      else
        echo "Gateway 服务未运行"
      fi
    fi
    ;;
  *)
    echo "用法: $0 {start|stop|restart|status}"
    echo ""
    echo "命令说明："
    echo "  start   - 启动 Gateway 服务"
    echo "  stop    - 停止 Gateway 服务"
    echo "  restart - 重启 Gateway 服务"
    echo "  status  - 查看服务状态"
    exit 1
    ;;
esac
