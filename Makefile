.PHONY: help setup up down restart logs status clean pull shell-openclaw shell-tailscale shell-n8n tailscale-status tailscale-auth

help:
	@echo "OpenClaw + Tailscale + n8n Docker Environment"
	@echo ""
	@echo "  make setup             Cài đặt ban đầu (sinh token, copy config)"
	@echo "  make up                Khởi động toàn bộ services"
	@echo "  make down              Dừng toàn bộ services"
	@echo "  make restart           Khởi động lại"
	@echo "  make logs              Xem log tất cả services"
	@echo "  make logs-openclaw     Xem log OpenClaw gateway"
	@echo "  make logs-tailscale    Xem log Tailscale proxy"
	@echo "  make logs-n8n          Xem log n8n"
	@echo "  make status            Trạng thái services"
	@echo "  make pull              Pull image mới nhất"
	@echo "  make clean             Dừng + xóa containers, volumes"
	@echo "  make shell-openclaw    Shell vào OpenClaw container"
	@echo "  make shell-tailscale   Shell vào Tailscale container"
	@echo "  make shell-n8n         Shell vào n8n container"
	@echo "  make tailscale-status  Kiểm tra Tailscale serve + funnel"
	@echo "  make tailscale-auth    Kiểm tra funnel authorization"
	@echo ""

setup:
	./scripts/setup.sh

up:
	docker compose up -d
	@echo ""
	@echo "Đợi ~30s rồi kiểm tra: make tailscale-status"

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

logs-openclaw:
	docker compose logs -f openclaw-gateway

logs-tailscale:
	docker compose logs -f tailscale-proxy

logs-n8n:
	docker compose logs -f n8n

status:
	@docker compose ps

pull:
	docker compose pull

shell-openclaw:
	docker compose exec openclaw-gateway sh

shell-tailscale:
	docker compose exec tailscale-proxy sh

shell-n8n:
	docker compose exec n8n sh

tailscale-status:
	@./scripts/tsctl.sh status

tailscale-auth:
	@./scripts/tsctl.sh auth

clean:
	docker compose down -v
	@echo "Đã dừng và xóa containers + volumes."
	@echo "Lưu ý: data/ và logs/ trên host KHÔNG bị xóa."
