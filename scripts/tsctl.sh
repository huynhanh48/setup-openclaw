#!/bin/bash
# Quản lý Tailscale proxy container
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

case "${1:-help}" in
  up)
    echo "==> Khởi động Tailscale proxy..."
    docker compose up -d tailscale-proxy
    echo ""
    echo "Xem logs:  ./scripts/tsctl.sh logs"
    echo "Kiểm tra:  ./scripts/tsctl.sh status"
    ;;
  down)
    echo "==> Dừng Tailscale proxy..."
    docker compose stop tailscale-proxy
    ;;
  restart)
    echo "==> Khởi động lại Tailscale proxy..."
    docker compose restart tailscale-proxy
    ;;
  logs)
    docker compose logs -f tailscale-proxy
    ;;
  status)
    echo "=== Tailscale Serve ==="
    docker exec tailscale-proxy tailscale serve status 2>/dev/null || echo "Container chưa chạy"
    echo ""
    echo "=== Tailscale Funnel ==="
    docker exec tailscale-proxy tailscale funnel status 2>/dev/null || echo "Container chưa chạy"
    echo ""
    echo "=== Tailscale Node ==="
    docker exec tailscale-proxy tailscale status 2>/dev/null || echo "Container chưa chạy"
    ;;
  ip)
    docker exec tailscale-proxy tailscale ip -4 2>/dev/null || echo "Container chưa chạy"
    ;;
  auth)
    echo "Kiểm tra funnel authorization..."
    docker exec tailscale-proxy tailscale funnel status 2>/dev/null
    echo ""
    echo "Nếu funnel chưa được authorize, truy cập URL hiển thị ở trên,"
    echo "hoặc vào: https://login.tailscale.com/admin/settings/funnel"
    ;;
  reconfig)
    echo "==> Cấu hình lại serve + funnel..."
    docker exec tailscale-proxy /bin/sh -c '
      tailscale serve --remove "${GATEWAY_ADDR}" 2>/dev/null || true
      tailscale serve --bg --https "${SERVE_PORT}" "${GATEWAY_ADDR}"
      tailscale funnel --bg --set-path "${FUNNEL_PATH}" "${GATEWAY_ADDR}${FUNNEL_PATH}"
    '
    echo "Done. Kiểm tra: ./scripts/tsctl.sh status"
    ;;
  shell)
    docker exec -it tailscale-proxy /bin/sh
    ;;
  help|*)
    echo "Usage: ./scripts/tsctl.sh <lệnh>"
    echo ""
    echo "Lệnh:"
    echo "  up        Khởi động Tailscale proxy container"
    echo "  down      Dừng container"
    echo "  restart   Khởi động lại container"
    echo "  logs      Xem log realtime"
    echo "  status    Hiển thị serve, funnel, node status"
    echo "  ip        Hiển thị Tailscale IP"
    echo "  auth      Kiểm tra funnel authorization"
    echo "  reconfig  Cấu hình lại serve + funnel"
    echo "  shell     Mở shell trong container"
    ;;
esac
