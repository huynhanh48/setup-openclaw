#!/usr/bin/env bash
# =============================================================================
#  tunnel.sh — SSH tunnel để truy cập OpenClaw từ xa (dev/debug)
#  Usage:
#    ./scripts/tunnel.sh up <user@host>    # Tạo SSH tunnel
#    ./scripts/tunnel.sh down              # Tắt tunnel
#    ./scripts/tunnel.sh status            # Kiểm tra tunnel
# =============================================================================
set -euo pipefail

TUNNEL_PORT="${TUNNEL_PORT:-18789}"
TUNNEL_HOST="${TUNNEL_HOST:-127.0.0.1}"
TUNNEL_PID_FILE="/tmp/openclaw-tunnel.pid"

case "${1:-help}" in
  up)
    REMOTE="${2:-}"
    if [ -z "$REMOTE" ]; then
      echo "Usage: ./scripts/tunnel.sh up <user@host>"
      echo "VD:    ./scripts/tunnel.sh up root@192.168.1.100"
      exit 1
    fi

    echo "==> Tạo SSH tunnel: localhost:${TUNNEL_PORT} -> ${REMOTE}:${TUNNEL_PORT}"
    ssh -N -L "${TUNNEL_PORT}:${TUNNEL_HOST}:${TUNNEL_PORT}" "$REMOTE" &
    TUNNEL_PID=$!
    echo "$TUNNEL_PID" > "$TUNNEL_PID_FILE"
    echo "Tunnel PID: $TUNNEL_PID"
    echo ""
    echo "OpenClaw Gateway: http://localhost:${TUNNEL_PORT}"
    echo "Tắt tunnel:        ./scripts/tunnel.sh down"
    ;;
  down)
    if [ -f "$TUNNEL_PID_FILE" ]; then
      TUNNEL_PID=$(cat "$TUNNEL_PID_FILE")
      echo "==> Tắt tunnel PID: $TUNNEL_PID"
      kill "$TUNNEL_PID" 2>/dev/null || true
      rm -f "$TUNNEL_PID_FILE"
      echo "Đã tắt."
    else
      echo "Không tìm thấy tunnel đang chạy."
    fi
    ;;
  status)
    if [ -f "$TUNNEL_PID_FILE" ]; then
      TUNNEL_PID=$(cat "$TUNNEL_PID_FILE")
      if kill -0 "$TUNNEL_PID" 2>/dev/null; then
        echo "Tunnel đang chạy (PID: $TUNNEL_PID)"
        echo "Gateway: http://localhost:${TUNNEL_PORT}"
      else
        echo "PID file tồn tại nhưng process đã chết. Dọn dẹp..."
        rm -f "$TUNNEL_PID_FILE"
      fi
    else
      echo "Không có tunnel đang chạy."
    fi
    ;;
  help|*)
    echo "Usage: ./scripts/tunnel.sh <lệnh> [args]"
    echo ""
    echo "Lệnh:"
    echo "  up <user@host>   Tạo SSH tunnel đến máy chủ Linux"
    echo "  down             Tắt tunnel"
    echo "  status           Kiểm tra trạng thái tunnel"
    echo ""
    echo "VD:"
    echo "  ./scripts/tunnel.sh up root@192.168.1.100"
    echo "  ./scripts/tunnel.sh status"
    echo "  ./scripts/tunnel.sh down"
    ;;
esac
