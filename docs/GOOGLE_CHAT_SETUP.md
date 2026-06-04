# Hướng dẫn cấu hình Google Chat trên Google Cloud Console

## 1. Tạo Project + Enable API

1. Vào [Google Cloud Console](https://console.cloud.google.com)
2. Tạo **New Project** (hoặc dùng project có sẵn)
3. APIs & Services → Library → Tìm "**Google Chat API**" → **Enable**
4. IAM & Admin → Service Accounts → **Create Service Account**
   - Tên: VD `openclaw-chat`
   - Role: không cần chọn role đặc biệt
5. Vào service account vừa tạo → Keys → **Add Key → Create New Key → JSON** → Download
6. Copy file JSON vào thư mục dự án:
   ```bash
   cp ~/Downloads/ten-file.json setup-agentic/data/openclaw/googlechat-service-account.json
   ```

## 2. Tạo Google Chat App

1. Google Cloud Console → APIs & Services → **Google Chat API** → **Configuration**
2. Điền thông tin:
   - **App name**: VD `MyBot`
   - **Avatar URL**: (tùy chọn)
   - **Description**: (tùy chọn)
3. **Functionality**: Check "**Join spaces and group conversations**"
4. **Connection settings**: Chọn "HTTP endpoint URL"
5. **Triggers**: Chọn "**Use a common HTTP endpoint URL for all triggers**"
6. **Endpoint URL**: `https://<your-funnel-hostname>/googlechat`
   - VD: `https://openclaw-gw.tailxxxxx.ts.net/googlechat`
7. **Visibility**: "Make this Chat app available to specific people..."
   - Thêm email người dùng trong domain
8. Nhấn **Save**

## 3. App Status → Live

1. Sau khi save, refresh trang
2. Tìm section **App status**
3. Set thành **Live - available to users**
4. **Save** lại

## 4. Cấu hình trong openclaw.json

Sửa file `data/openclaw/openclaw.json`:

```json
{
  "channels": {
    "googlechat": {
      "enabled": true,
      "serviceAccountFile": "/home/node/.openclaw/googlechat-service-account.json",
      "audienceType": "app-url",
      "audience": "https://<your-funnel-hostname>/googlechat",
      "appPrincipal": "<client_id từ service account JSON>",
      "webhookPath": "/googlechat",
      "webhookUrl": "https://<your-funnel-hostname>/googlechat",
      "groupPolicy": "open",
      "groups": {},
      "actions": { "reactions": true }
    }
  }
}
```

> **⚠️ QUAN TRỌNG:**
> - `audience` PHẢI khớp chính xác với Endpoint URL trên Google Cloud Console
> - `appPrincipal` là `client_id` từ file service account JSON (dạng số)
> - Nếu dùng Tailscale Funnel: hostname là `<node-name>.<tailnet>.ts.net`

## 5. Public Webhook (Tailscale Funnel)

Funnel được tự động cấu hình khi container Tailscale khởi động.

Sau khi container chạy ~30s, kiểm tra và authorize:

```bash
# Kiểm tra trạng thái
./scripts/tsctl.sh status
./scripts/tsctl.sh auth

# Nếu funnel chưa được authorize, truy cập URL hiển thị
# hoặc vào: https://login.tailscale.com/admin/settings/funnel
```

Nếu không dùng Tailscale, có thể dùng:
- **Caddy / Nginx** reverse proxy + Let's Encrypt
- **Cloudflare Tunnel** (`cloudflared`)
- **ngrok** (cho dev/test)

## 6. Các lỗi thường gặp

| # | Lỗi | Nguyên nhân | Cách fix |
|---|-----|-------------|----------|
| 1 | Bot không respond trong group | `requireMention: true` mặc định | Set `requireMention: false` hoặc dùng `@bot` mention |
| 2 | Chỉ respond được 1 số space | `groupPolicy: "allowlist"` cần whitelist | Đổi thành `groupPolicy: "open"` |
| 3 | Codex hit usage limit | Hết quota Codex subscription | Đã có fallbacks trong config |
| 4 | `parseMediaContentLength is not a function` | Plugin version không khớp gateway | Cài đúng version plugin (`@openclaw/googlechat@<version>`) |
| 5 | `Wrong recipient, payload audience != requiredAudience` | `audience` trong config khác webhook URL thật | Sửa `audience` khớp với URL trên Google Cloud Console |
| 6 | `message` tool bị mất | `tools.profile: "coding"` ẩn tool | Đổi profile thành `"full"` hoặc cấu hình `tools.allow` |
| 7 | No logs từ Google Chat | Webhook không reachable hoặc plugin chết | Kiểm tra Tailscale Funnel + plugin version |
| 8 | External user không gửi được cho bot | Google Chat app private chỉ nhận trong domain | Publish lên Google Workspace Marketplace (internal listing) |
| 9 | "Allow external members to join" greyed out | Chỉ set được khi tạo space mới | Xóa space → tạo lại, bật option ngay từ đầu |
| 10 | External members can't post | Space default "Only owners and managers can post" | Khi tạo space → bỏ chọn "Only managers can post" |

## 7. CLI hữu ích (trong container OpenClaw)

```bash
# Vào container
docker compose exec openclaw-gateway sh

# Validate config
node dist/index.js config validate

# Check channel status
node dist/index.js channels status
node dist/index.js status --deep

# Xem sessions
node dist/index.js sessions list

# Restart gateway (in-process)
kill -USR1 1

# Xem log file
tail -100 /tmp/openclaw/openclaw-$(date -u +%F).log | grep -i googlechat

# Check plugin version
cat /home/node/.openclaw/npm/node_modules/@openclaw/googlechat/package.json | grep version
```

## 8. Xử lý External Users

Google Chat App **private** (chưa publish Marketplace):
- Chỉ add được email trong cùng Google Workspace domain
- External user trong space không gửi được MESSAGE event → bot không nhận mention

**Cách fix duy nhất:** Publish Google Chat App lên Google Workspace Marketplace:
1. Google Cloud Console → **Google Workspace Marketplace SDK** → **Configuration**
2. Tạo app listing (chọn **internal** — không cần public)
3. Set Visibility: "Make available to anyone in `<domain>`"
4. Publish → bot nhận được tương tác từ external user
