# 🐳 OpenClaw + Tailscale + n8n — Docker Environment

Triển khai **OpenClaw Gateway** tích hợp **Google Chat channel**, **Tailscale Funnel** reverse proxy, và **n8n** workflow automation trong Docker. Một lệnh `docker compose up -d` để chạy toàn bộ 3 services.

---

## Kiến trúc

```
[Google Chat App] ──→ webhook HTTPS ──→ [Tailscale Funnel]
                                              │
                              ┌───────────────┤
                              ▼               ▼
                     [OpenClaw :18789]  [n8n :5678]
                              │
                              ▼
                     [Models: Codex / OpenCode-Go]
```

**3 services trong 1 compose file:**

| Service | Container | Port | Vai trò |
|---------|-----------|------|---------|
| `openclaw-gateway` | `openclaw-gateway` | 18789, 18790 | AI Gateway + Google Chat bot |
| `tailscale-proxy` | `tailscale-proxy` | host network | Tailscale Funnel → public webhook |
| `n8n` | `n8n` | 5678 | Workflow automation

---

## Yêu cầu

- **Docker** + **Docker Compose v2**
- **Tailscale** account (free) + auth key
- **Google Cloud** project với Google Chat API đã enable
- Service account JSON cho Google Chat

---

## Bắt đầu trên VPS mới (Ubuntu/Debian)

```bash
# 1. Cài Docker (nếu chưa có)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# 2. Clone repo
git clone <repo-url> setup-agentic && cd setup-agentic

# 3. Chạy wizard — làm theo từng bước
./scripts/setup.sh
```

**Thế thôi.** Script sẽ hỏi bạn từng thứ một:
- Dán Tailscale auth key (vào tailscale.com lấy trước)
- Chạy onboarding OpenClaw (dán API key Codex/OpenCode)
- Đường dẫn file JSON Google Chat (upload lên VPS trước)
- Email + hostname + client_id

Sau khi script chạy xong, tất cả services đã up, funnel đã được nhắc authorize.

### Cần chuẩn bị trước

| Thứ cần có | Lấy ở đâu |
|------------|-----------|
| Tailscale auth key | https://login.tailscale.com/admin/settings/keys → Generate key |
| Codex/OpenCode API key | Dashboard của provider |
| Google Chat SA JSON | Google Cloud Console → Service Accounts → Key → JSON → Upload lên VPS |

---

## Cấu trúc thư mục

```
setup-agentic/
├── docker-compose.yml              # Orchestration cho 3 services + 1 CLI
├── .env.template                   # Template biến môi trường
├── .env                            # Biến môi trường thực (gitignored)
├── Makefile                        # Shortcuts: make up/down/logs...
├── README.md                       # File này
│
├── config/
│   ├── openclaw.json               # Config OpenClaw (agents, channels, plugins, auth, gateway, tools)
│   └── googlechat-service-account.json.example
│
├── scripts/
│   ├── setup.sh                    # Wizard tương tác — chạy 1 file, làm hết
│   ├── entrypoint-tailscale.sh     # Tailscale entrypoint
│   ├── tsctl.sh                    # Quản lý Tailscale
│   └── tunnel.sh                   # SSH tunnel helper
│
├── docs/
│   └── GOOGLE_CHAT_SETUP.md        # Hướng dẫn GCP + Google Chat
│
├── data/                           # Runtime data (gitignored)
│   ├── openclaw/                   # Mount → /home/node/.openclaw
│   ├── tailscale/                  # Mount → /var/lib/tailscale
│   └── n8n/                        # Mount → /home/node/.n8n
│
└── logs/                           # OpenClaw logs persist (gitignored)
```

---

## Các lệnh thường dùng

```bash
make help              # Hiển thị tất cả lệnh
make setup             # Chạy wizard cài đặt (tương tác từng bước)
make up                # Khởi động 3 services
make down              # Dừng services
make restart           # Khởi động lại
make logs              # Xem log (tất cả)
make logs-openclaw     # Xem log OpenClaw
make logs-tailscale    # Xem log Tailscale
make logs-n8n          # Xem log n8n
make status            # Trạng thái containers
make shell-openclaw    # Shell vào OpenClaw container
make shell-tailscale   # Shell vào Tailscale container
make shell-n8n         # Shell vào n8n container
make tailscale-status  # Kiểm tra serve + funnel
make tailscale-auth    # Kiểm tra funnel authorization
make pull              # Pull image mới nhất
make clean             # Dừng + xóa containers, volumes
```

---

## Fallback Models

Khi Codex bị rate-limit, gateway tự động chuyển sang các model dự phòng:

| Thứ tự | Model |
|--------|-------|
| 1 (primary) | `codex/gpt-5.4` |
| 2 | `opencode-go/deepseek-v4-flash` |
| 3 | `opencode-go/qwen3.6-plus` |
| 4 | `opencode-go/minimax-m2.7` |
| 5 | `opencode-go/glm-5` |

Cấu hình trong `data/openclaw/openclaw.json` → `agents.defaults.model.fallbacks`.

---

## Plugin Version Compatibility

> **⚠️ Plugin `@openclaw/googlechat` PHẢI khớp version với gateway.**

Kiểm tra:
```bash
# Trong OpenClaw container
docker compose exec openclaw-gateway cat /home/node/.openclaw/npm/node_modules/@openclaw/googlechat/package.json | grep version
```

Nếu version không khớp, lỗi: `parseMediaContentLength is not a function`.

---

## Cấu hình Google Chat

Xem chi tiết: [`docs/GOOGLE_CHAT_SETUP.md`](docs/GOOGLE_CHAT_SETUP.md)

Tóm tắt các bước:
1. Tạo GCP project → Enable Google Chat API
2. Tạo Service Account → Download JSON key
3. Tạo Google Chat App → HTTP endpoint URL = `https://<hostname>/googlechat`
4. Set App Status = Live
5. Copy JSON vào `data/openclaw/googlechat-service-account.json`

---

## Docker Container Restart

Trong Docker, `openclaw gateway restart` không hoạt động (không có systemd).

Cách restart:
```bash
# Khởi động lại container (recommended)
docker compose restart openclaw-gateway

# Hoặc in-process restart (từ trong container)
docker compose exec openclaw-gateway kill -USR1 1
```

---

## Log files

Mặc định log nằm trong container tại `/tmp/openclaw/openclaw-YYYY-MM-DD.log`.

Đã mount volume để persist log ra host:
```bash
# Xem log từ host
tail -100 logs/openclaw-$(date -u +%F).log | grep -i googlechat

# Xem log từ container
docker compose exec openclaw-gateway tail -100 /tmp/openclaw/openclaw-$(date -u +%F).log
```

---

## Upgrade

```bash
# Pull image mới
docker compose pull

# Khởi động lại
docker compose up -d

# Backup config trước khi upgrade
cp data/openclaw/openclaw.json data/openclaw/openclaw.json.bak.$(date +%Y%m%d)
```

---

## Troubleshooting nhanh

| Vấn đề | Kiểm tra |
|--------|----------|
| Webhook không nhận request | `./scripts/tsctl.sh status` — funnel đã authorized chưa? |
| Bot không reply | `docker compose logs openclaw-gateway \| grep -i googlechat` |
| Codex rate-limit | Kiểm tra fallback đã hoạt động: `docker compose logs openclaw-gateway \| grep -i fallback` |
| Plugin error | Check version match giữa plugin và gateway |
| Tailscale không kết nối | `docker compose exec tailscale-proxy tailscale status` |
