#!/usr/bin/env bash
# =============================================================================
#  setup.sh — Interactive Setup Wizard
#  OpenClaw + Tailscale + n8n Docker Environment
#  Chạy: ./scripts/setup.sh — làm theo từng bước, không cần làm gì thêm.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()   { echo -e "${BLUE}  →${NC} $*"; }
ok()     { echo -e "${GREEN}  ✓${NC} $*"; }
warn()   { echo -e "${YELLOW}  ⚠${NC} $*"; }
err()    { echo -e "${RED}  ✗${NC} $*"; }
step()   { echo -e "\n${BOLD}${CYAN}━━━ $* ━━━${NC}"; }
prompt() { echo -en "${BOLD}  ›${NC} $*: "; }
press_enter() { read -rp "$(echo -e "${BOLD}  ›${NC} Nhấn Enter để tiếp tục...")"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ===================================================================
# Banner
# ===================================================================
clear 2>/dev/null || true
echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║       OpenClaw + Tailscale + n8n — Setup Wizard         ║"
echo "  ║       Làm theo từng bước, script sẽ tự xử lý.           ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

# ===================================================================
# Step 1 — Kiểm tra dependencies
# ===================================================================
step "Bước 1/7 — Kiểm tra môi trường"

if ! command -v docker >/dev/null 2>&1; then
  err "Docker chưa được cài đặt."
  echo "  Cài đặt: curl -fsSL https://get.docker.com | sh"
  exit 1
fi
ok "Docker: $(docker --version 2>/dev/null | head -1)"

if ! docker compose version >/dev/null 2>&1; then
  err "Docker Compose không khả dụng."
  exit 1
fi
ok "Docker Compose: OK"

ok "Môi trường sẵn sàng!"

# ===================================================================
# Step 2 — Sinh token, tạo file, copy config
# ===================================================================
step "Bước 2/7 — Khởi tạo cấu hình"

# --- Tạo .env nếu chưa có ---
if [ ! -f "$PROJECT_DIR/.env" ]; then
  cp "$PROJECT_DIR/.env.template" "$PROJECT_DIR/.env"
  ok "Đã tạo .env từ template."
else
  info ".env đã tồn tại, bỏ qua."
fi

# --- Hàm sinh token ---
gen_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32
  else
    python3 -c "import secrets; print(secrets.token_hex(32))"
  fi
}

# --- Sinh OpenClaw gateway token ---
if ! grep -q 'OPENCLAW_GATEWAY_TOKEN=' "$PROJECT_DIR/.env" 2>/dev/null || \
   grep -q 'OPENCLAW_GATEWAY_TOKEN=$' "$PROJECT_DIR/.env" 2>/dev/null; then
  TOKEN=$(gen_token)
  if grep -q 'OPENCLAW_GATEWAY_TOKEN=' "$PROJECT_DIR/.env"; then
    sed -i.bak "s/^OPENCLAW_GATEWAY_TOKEN=.*/OPENCLAW_GATEWAY_TOKEN=${TOKEN}/" "$PROJECT_DIR/.env"
  else
    echo "OPENCLAW_GATEWAY_TOKEN=${TOKEN}" >> "$PROJECT_DIR/.env"
  fi
  ok "Đã sinh gateway token: ${TOKEN:0:16}..."
else
  ok "Gateway token đã có sẵn."
fi

# --- Sinh n8n encryption key ---
if ! grep -q 'N8N_ENCRYPTION_KEY=' "$PROJECT_DIR/.env" 2>/dev/null || \
   grep -q 'N8N_ENCRYPTION_KEY=$' "$PROJECT_DIR/.env" 2>/dev/null; then
  N8N_KEY=$(gen_token)
  if grep -q 'N8N_ENCRYPTION_KEY=' "$PROJECT_DIR/.env"; then
    sed -i.bak "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=${N8N_KEY}/" "$PROJECT_DIR/.env"
  else
    echo "N8N_ENCRYPTION_KEY=${N8N_KEY}" >> "$PROJECT_DIR/.env"
  fi
  ok "Đã sinh n8n encryption key: ${N8N_KEY:0:16}..."
else
  ok "n8n encryption key đã có sẵn."
fi

# --- Tạo thư mục ---
mkdir -p "$PROJECT_DIR/data/openclaw/workspace"
mkdir -p "$PROJECT_DIR/data/tailscale"
mkdir -p "$PROJECT_DIR/data/n8n"
mkdir -p "$PROJECT_DIR/logs"
ok "Thư mục data/ đã sẵn sàng."

# --- Copy config + tự động thay token ---
if [ ! -f "$PROJECT_DIR/data/openclaw/openclaw.json" ]; then
  cp "$PROJECT_DIR/config/openclaw.json" "$PROJECT_DIR/data/openclaw/openclaw.json"
  ok "Đã copy openclaw.json → data/openclaw/."
else
  info "openclaw.json đã tồn tại."
fi

ACTUAL_TOKEN=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$PROJECT_DIR/.env" 2>/dev/null | cut -d= -f2-)
if [ -n "$ACTUAL_TOKEN" ] && grep -q '__GENERATED_TOKEN__' "$PROJECT_DIR/data/openclaw/openclaw.json"; then
  sed -i.bak "s/__GENERATED_TOKEN__/${ACTUAL_TOKEN}/" "$PROJECT_DIR/data/openclaw/openclaw.json"
  ok "Đã tự động điền gateway token vào openclaw.json."
fi
rm -f "$PROJECT_DIR/data/openclaw/openclaw.json.bak"

# ===================================================================
# Step 3 — Tailscale Auth Key
# ===================================================================
step "Bước 3/7 — Tailscale Auth Key"

echo ""
echo "  Tailscale cần 1 auth key để kết nối node vào tailnet của bạn."
echo ""
echo "  Cách lấy:"
echo "    1. Mở: https://login.tailscale.com/admin/settings/keys"
echo "    2. Nhấn 'Generate auth key...'"
echo "    3. Chọn 'Reusable', nhấn 'Generate key'"
echo "    4. Copy key (dạng tskey-auth-xxxxxxxxxxxxx)"
echo ""

TSKEY=""
while [ -z "$TSKEY" ]; do
  prompt "Dán Tailscale auth key vào đây"
  read -r TSKEY
  if [ -z "$TSKEY" ]; then
    warn "Auth key không được để trống. Vui lòng dán key vào."
    echo ""
  fi
done

if grep -q '^TS_AUTHKEY=' "$PROJECT_DIR/.env"; then
  sed -i.bak "s|^TS_AUTHKEY=.*|TS_AUTHKEY=${TSKEY}|" "$PROJECT_DIR/.env"
else
  echo "TS_AUTHKEY=${TSKEY}" >> "$PROJECT_DIR/.env"
fi
rm -f "$PROJECT_DIR/.env.bak"
ok "Đã lưu Tailscale auth key vào .env!"

# ===================================================================
# Step 4 — OpenClaw Onboarding (thêm API key)
# ===================================================================
step "Bước 4/7 — Onboarding OpenClaw (thêm tài khoản AI)"

echo ""
echo "  Bây giờ script sẽ chạy wizard onboarding của OpenClaw."
echo "  Wizard sẽ hỏi bạn từng bước:"
echo "    - Gateway bind:       chọn 'lan'"
echo "    - Auth mode:          chọn 'token'"
echo "    - Gateway token:      đã được sinh tự động"
echo "    - Provider API keys:  dán key Codex / OpenCode / OpenAI..."
echo ""
echo "  ⚠  QUAN TRỌNG: Cần có sẵn API key trước khi chạy bước này."
echo "     - Codex:      đăng nhập qua OAuth (browser)"
echo "     - OpenCode:    API key từ dashboard OpenCode/OpenCode-Go"
echo "     - OpenAI:      API key từ https://platform.openai.com/api-keys"
echo ""

while true; do
  prompt "Bạn đã sẵn sàng chạy onboarding? (y/n)"
  read -r ans
  case "$ans" in
    [Yy]* ) break;;
    [Nn]* )
      warn "Bỏ qua onboarding. Bạn có thể chạy lại sau:"
      echo "         docker compose run --rm openclaw-cli onboard --no-install-daemon"
      echo ""
      break;;
    * ) warn "Vui lòng trả lời y hoặc n.";;
  esac
done

if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
  echo ""
  info "Đang chạy onboarding..."
  echo ""
  docker compose -f "$PROJECT_DIR/docker-compose.yml" run --rm openclaw-cli onboard --no-install-daemon || {
    warn "Onboarding gặp lỗi hoặc bị huỷ. Có thể chạy lại sau."
  }
fi

# ===================================================================
# Step 5 — Google Chat Service Account JSON
# ===================================================================
step "Bước 5/7 — Google Chat Service Account"

echo ""
echo "  Cần file JSON service account từ Google Cloud Console."
echo ""
echo "  Cách lấy (nếu chưa có):"
echo "    1. Vào Google Cloud Console → IAM & Admin → Service Accounts"
echo "    2. Chọn service account → Keys → Add Key → JSON → Download"
echo "    3. Upload file JSON lên VPS (scp, rsync, hoặc copy-paste)"
echo ""
echo "  Nếu chưa có, bạn có thể skip bước này và làm sau."
echo ""

while true; do
  prompt "Đường dẫn tới file JSON service account (để trống để bỏ qua)"
  read -r sa_path
  if [ -z "$sa_path" ]; then
    warn "Bỏ qua — bạn có thể copy file JSON vào data/openclaw/googlechat-service-account.json sau."
    break
  fi
  if [ -f "$sa_path" ]; then
    cp "$sa_path" "$PROJECT_DIR/data/openclaw/googlechat-service-account.json"
    ok "Đã copy service account JSON vào data/openclaw/."
    break
  else
    err "Không tìm thấy file: $sa_path"
    echo ""
  fi
done

# ===================================================================
# Step 6 — Điền placeholder trong openclaw.json
# ===================================================================
step "Bước 6/7 — Cấu hình Google Chat channel"

CONFIG_FILE="$PROJECT_DIR/data/openclaw/openclaw.json"
NEEDS_EDIT=false

if grep -q '__YOUR_EMAIL__' "$CONFIG_FILE" 2>/dev/null; then NEEDS_EDIT=true; fi
if grep -q '__YOUR_HOSTNAME__' "$CONFIG_FILE" 2>/dev/null; then NEEDS_EDIT=true; fi
if grep -q '__YOUR_CLIENT_ID__' "$CONFIG_FILE" 2>/dev/null; then NEEDS_EDIT=true; fi

if [ "$NEEDS_EDIT" = true ]; then
  echo ""
  echo "  Cần điền 3 thông tin vào data/openclaw/openclaw.json:"
  echo ""

  # Email
  if grep -q '__YOUR_EMAIL__' "$CONFIG_FILE" 2>/dev/null; then
    echo "  ① Email Codex/OpenAI:"
    prompt "    Nhập email"
    read -r email
    if [ -n "$email" ]; then
      sed -i.bak "s/__YOUR_EMAIL__/${email}/g" "$CONFIG_FILE"
      ok "    Đã lưu: $email"
    fi
  fi

  # Hostname
  if grep -q '__YOUR_HOSTNAME__' "$CONFIG_FILE" 2>/dev/null; then
    echo ""
    echo "  ② Tailscale Funnel hostname (VD: openclaw-gw.tailxxxxx.ts.net):"
    echo "     (Hostname sẽ có sau khi Tailscale kết nối. Có thể để tạm và sửa sau.)"
    prompt "    Nhập hostname"
    read -r hostname
    if [ -n "$hostname" ]; then
      sed -i.bak "s|__YOUR_HOSTNAME__|${hostname}|g" "$CONFIG_FILE"
      ok "    Đã lưu: $hostname"
    fi
  fi

  # Client ID
  if grep -q '__YOUR_CLIENT_ID__' "$CONFIG_FILE" 2>/dev/null; then
    echo ""
    echo "  ③ Google Chat App Principal (client_id từ service account JSON):"
    echo "     (Mở file JSON → tìm trường 'client_id' → copy số)"
    prompt "    Nhập client_id"
    read -r client_id
    if [ -n "$client_id" ]; then
      sed -i.bak "s/__YOUR_CLIENT_ID__/${client_id}/g" "$CONFIG_FILE"
      ok "    Đã lưu: $client_id"
    fi
  fi

  rm -f "$CONFIG_FILE.bak"
  echo ""
  ok "Đã cập nhật openclaw.json!"
else
  ok "openclaw.json đã được cấu hình đầy đủ."
fi

# ===================================================================
# Step 7 — Khởi động
# ===================================================================
step "Bước 7/7 — Khởi động toàn bộ services"

echo ""
echo "  Sẵn sàng khởi động 3 services:"
echo "    • openclaw-gateway   (port 18789)"
echo "    • tailscale-proxy    (network host)"
echo "    • n8n                (port 5678)"
echo ""

while true; do
  prompt "Khởi động ngay bây giờ? (y/n)"
  read -r ans
  case "$ans" in
    [Yy]* ) break;;
    [Nn]* )
      echo ""
      info "Bạn có thể khởi động sau bằng lệnh:"
      echo "       docker compose pull && docker compose up -d"
      echo ""
      ok "Setup hoàn tất! Hẹn gặp lại."
      exit 0;;
    * ) warn "Vui lòng trả lời y hoặc n.";;
  esac
done

echo ""
info "Đang pull images..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" pull

echo ""
info "Đang khởi động services..."
docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d

echo ""
info "Đợi services khởi động (~45 giây)..."
sleep 15
docker compose -f "$PROJECT_DIR/docker-compose.yml" ps

sleep 15
echo ""
info "Kiểm tra trạng thái..."

STATUS=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --format json 2>/dev/null | python3 -c "
import sys, json
lines = sys.stdin.read().strip().split('\n')
healthy = 0
total = 0
for line in lines:
    if not line: continue
    d = json.loads(line)
    total += 1
    name = d.get('Name','?')
    state = d.get('State','?')
    health = d.get('Health','?')
    print(f'  {name}: {state} ({health})')
    if health == 'healthy': healthy += 1
print(f'\n  {healthy}/{total} services healthy')
" 2>/dev/null || docker compose -f "$PROJECT_DIR/docker-compose.yml" ps)

# ===================================================================
# Tailscale Funnel Authorization
# ===================================================================
echo ""
step "Authorize Tailscale Funnel"

echo ""
echo "  Tailscale Funnel cần được authorize để Google Chat"
echo "  có thể gửi webhook tới bot của bạn qua internet."
echo ""

if docker exec tailscale-proxy tailscale funnel status >/dev/null 2>&1; then
  docker exec tailscale-proxy tailscale funnel status 2>&1 || true
fi

echo ""
while true; do
  prompt "Bạn đã authorize funnel chưa? (y/n)"
  read -r ans
  case "$ans" in
    [Yy]* )
      ok "Đã authorize!"
      break;;
    [Nn]* )
      echo ""
      echo "  Các bước authorize:"
      echo "    1. Chạy: docker exec tailscale-proxy tailscale funnel status"
      echo "    2. Mở URL hiển thị trong browser"
      echo "    3. Hoặc vào: https://login.tailscale.com/admin/settings/funnel"
      echo "    4. Tìm node '${TS_HOSTNAME:-openclaw-gw}' → Enable funnel"
      echo ""
      warn "Hãy authorize trước khi test Google Chat webhook."
      break;;
    * ) warn "Vui lòng trả lời y hoặc n.";;
  esac
done

# ===================================================================
# Done
# ===================================================================
echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║                    SETUP HOÀN TẤT!                      ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Services đang chạy:"
echo "    • OpenClaw Gateway:  http://localhost:18789"
echo "    • n8n:               http://localhost:5678"
echo ""
echo "  Lệnh hữu ích:"
echo "    docker compose ps                  — Trạng thái"
echo "    docker compose logs -f             — Xem log"
echo "    ./scripts/tsctl.sh status          — Kiểm tra Tailscale"
echo "    ./scripts/tsctl.sh auth            — Authorize funnel"
echo "    make help                          — Tất cả lệnh"
echo ""
echo "  Webhook URL cho Google Chat Console:"
echo "    https://<hostname>/googlechat"
echo "    (Hostname = node-name.tailnet.ts.net — xem qua 'make tailscale-status')"
echo ""
