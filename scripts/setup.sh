#!/usr/bin/env bash
# =============================================================================
#  setup.sh — Cài đặt OpenClaw + Tailscale Docker Environment
#  Usage: ./scripts/setup.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo ""
echo "================================================"
echo "  OpenClaw + Tailscale + n8n — Setup"
echo "================================================"
echo ""

# --- 1. Kiểm tra dependencies ---
info "Kiểm tra dependencies..."

if ! command -v docker >/dev/null 2>&1; then
  err "Docker chưa được cài đặt. Cài đặt: https://docs.docker.com/engine/install/"
  exit 1
fi
ok "Docker: $(docker --version)"

if ! docker compose version >/dev/null 2>&1; then
  err "Docker Compose không khả dụng."
  exit 1
fi
ok "Docker Compose: $(docker compose version --short 2>/dev/null || echo 'OK')"

if ! command -v openssl >/dev/null 2>&1; then
  warn "openssl không có sẵn, dùng python3 để sinh token."
fi

# --- 2. Tạo .env nếu chưa có ---
if [ ! -f "$PROJECT_DIR/.env" ]; then
  info "Tạo .env từ .env.template..."
  cp "$PROJECT_DIR/.env.template" "$PROJECT_DIR/.env"
  ok ".env đã được tạo."
else
  info ".env đã tồn tại, bỏ qua."
fi

# --- 3. Sinh gateway token nếu chưa có ---
gen_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    python3 -c "import secrets; print(secrets.token_hex(32))"
  fi
}

if grep -q '__GENERATED_TOKEN__' "$PROJECT_DIR/.env" 2>/dev/null || \
   ! grep -q 'OPENCLAW_GATEWAY_TOKEN=' "$PROJECT_DIR/.env" 2>/dev/null || \
   grep -q 'OPENCLAW_GATEWAY_TOKEN=$' "$PROJECT_DIR/.env" 2>/dev/null; then

  info "Sinh OpenClaw gateway token..."
  TOKEN=$(gen_token)

  if grep -q 'OPENCLAW_GATEWAY_TOKEN=' "$PROJECT_DIR/.env"; then
    sed -i.bak "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=${TOKEN}/" "$PROJECT_DIR/.env"
  else
    echo "OPENCLAW_GATEWAY_TOKEN=${TOKEN}" >> "$PROJECT_DIR/.env"
  fi
  ok "Gateway token đã được sinh: ${TOKEN:0:16}..."
else
  ok "OPENCLAW_GATEWAY_TOKEN đã được cấu hình."
fi

# --- 3b. Sinh n8n encryption key nếu chưa có ---
if ! grep -q 'N8N_ENCRYPTION_KEY=' "$PROJECT_DIR/.env" 2>/dev/null || \
   grep -q 'N8N_ENCRYPTION_KEY=$' "$PROJECT_DIR/.env" 2>/dev/null; then

  info "Sinh n8n encryption key..."
  N8N_KEY=$(gen_token)

  if grep -q 'N8N_ENCRYPTION_KEY=' "$PROJECT_DIR/.env"; then
    sed -i.bak "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=${N8N_KEY}/" "$PROJECT_DIR/.env"
  else
    echo "N8N_ENCRYPTION_KEY=${N8N_KEY}" >> "$PROJECT_DIR/.env"
  fi
  ok "n8n encryption key đã được sinh: ${N8N_KEY:0:16}..."
else
  ok "N8N_ENCRYPTION_KEY đã được cấu hình."
fi

# --- 4. Tạo thư mục data nếu chưa có ---
info "Tạo thư mục data..."
mkdir -p "$PROJECT_DIR/data/openclaw/workspace"
mkdir -p "$PROJECT_DIR/data/tailscale"
mkdir -p "$PROJECT_DIR/data/n8n"
mkdir -p "$PROJECT_DIR/logs"
ok "Thư mục data đã sẵn sàng."

# --- 5. Copy config vào data/openclaw ---
info "Cấu hình OpenClaw..."

if [ ! -f "$PROJECT_DIR/data/openclaw/openclaw.json" ]; then
  if [ -f "$PROJECT_DIR/config/openclaw.json" ]; then
    cp "$PROJECT_DIR/config/openclaw.json" "$PROJECT_DIR/data/openclaw/openclaw.json"
    ok "openclaw.json đã được copy vào data/openclaw/."
  else
    warn "Không tìm thấy config/openclaw.json — bỏ qua."
  fi
else
  info "data/openclaw/openclaw.json đã tồn tại, bỏ qua."
fi

# --- 6. Nhắc copy service account JSON ---
echo ""
info "=== CÁC BƯỚC TIẾP THEO ==="
echo ""
echo "1. Copy Google Chat service account JSON:"
echo "   cp <đường-dẫn>/googlechat-service-account.json \\"
echo "      $PROJECT_DIR/data/openclaw/googlechat-service-account.json"
echo ""
echo "2. Sửa data/openclaw/openclaw.json — thay thế các placeholder:"
echo "   - __YOUR_EMAIL__     → email Codex/OpenAI của bạn"
echo "   - __YOUR_HOSTNAME__  → public hostname (VD: openclaw-gw.tailxxxx.ts.net)"
echo "   - __YOUR_CLIENT_ID__ → client_id từ service account JSON"
echo ""
echo "3. Sửa .env — điền Tailscale TS_AUTHKEY và các biến môi trường."
echo ""
echo "4. Sau khi cấu hình xong:"
echo "   docker compose pull          # Pull image mới nhất"
echo "   docker compose up -d         # Khởi động toàn bộ 3 services"
echo "   docker compose ps            # Kiểm tra trạng thái"
echo "   docker compose logs -f       # Theo dõi log"
echo ""
echo "5. Authorize Tailscale Funnel (sau khi container chạy ~30s):"
echo "   ./scripts/tsctl.sh auth"
echo ""
echo "6. Truy cập n8n: http://<vps-ip>:5678"
echo ""
echo "================================================"
ok "Setup hoàn tất!"
echo ""
