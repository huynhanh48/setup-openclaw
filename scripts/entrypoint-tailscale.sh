#!/bin/sh
set -e

GATEWAY_ADDR="${GATEWAY_ADDR:-http://127.0.0.1:18789}"
SERVE_PORT="${SERVE_PORT:-8443}"
FUNNEL_PATH="${FUNNEL_PATH:-/googlechat}"

echo "============================================"
echo "  Tailscale Proxy — OpenClaw Gateway"
echo "============================================"
echo "Gateway:  ${GATEWAY_ADDR}"
echo "Serve:    :${SERVE_PORT} -> ${GATEWAY_ADDR}"
echo "Funnel:   ${FUNNEL_PATH} -> ${GATEWAY_ADDR}${FUNNEL_PATH}"
echo "============================================"

# --- Start Tailscale ---
echo "[tailscale] Starting daemon..."
/usr/local/bin/containerboot &
BOOT_PID=$!

echo "[tailscale] Waiting for Tailscale to come online..."
for i in $(seq 1 60); do
  if tailscale status >/dev/null 2>&1; then
    echo "[tailscale] Online!"
    break
  fi
  sleep 1
done

if ! tailscale status >/dev/null 2>&1; then
  echo "[tailscale] ERROR: Not online after 60s"
  exit 1
fi

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1)
echo "[tailscale] IP: ${TAILSCALE_IP}"

# --- Wait for gateway ---
echo "[tailscale] Waiting for gateway at ${GATEWAY_ADDR}..."
for i in $(seq 1 60); do
  if curl -s --max-time 2 "${GATEWAY_ADDR}" >/dev/null 2>&1; then
    echo "[tailscale] Gateway reachable!"
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "[tailscale] WARNING: Gateway not reachable at ${GATEWAY_ADDR}"
    echo "[tailscale] Serve/funnel will be configured, but may fail until gateway is up."
  fi
  sleep 2
done

# --- Remove old config (idempotent) ---
tailscale serve --remove "${GATEWAY_ADDR}" 2>/dev/null || true

# --- Configure Tailscale Serve (private, tailnet only) ---
echo "[tailscale] Configuring serve: tailscale serve --bg --https ${SERVE_PORT} ${GATEWAY_ADDR}"
if tailscale serve --bg --https "${SERVE_PORT}" "${GATEWAY_ADDR}" 2>/dev/null; then
  echo "[tailscale] Serve OK!"
else
  echo "[tailscale] Serve may already be configured, continuing..."
fi

# --- Configure Tailscale Funnel (public, specific path only) ---
echo "[tailscale] Configuring funnel: tailscale funnel --bg --set-path ${FUNNEL_PATH} ${GATEWAY_ADDR}${FUNNEL_PATH}"
if tailscale funnel --bg --set-path "${FUNNEL_PATH}" "${GATEWAY_ADDR}${FUNNEL_PATH}" 2>/dev/null; then
  echo "[tailscale] Funnel OK!"
else
  echo "[tailscale] WARNING: Funnel setup failed or needs authorization."
  echo "[tailscale] Run: docker exec tailscale-proxy tailscale funnel status"
fi

# --- Summary ---
echo ""
echo "============================================"
echo "  CONFIGURATION SUMMARY"
echo "============================================"
echo "Node IP:       ${TAILSCALE_IP}"
echo "Private Serve: https://${TAILSCALE_IP}:${SERVE_PORT}"
echo "Funnel status:"
tailscale funnel status 2>/dev/null || echo "  (not authorized yet)"
echo "============================================"
echo "Webhook URL cho Google Chat Console:"
echo "  https://<hostname>${FUNNEL_PATH}"
echo "============================================"

# --- Keep alive ---
wait $BOOT_PID
