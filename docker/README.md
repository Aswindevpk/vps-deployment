# Docker architecture

Docker runs your **app stack** (web, Celery, Postgres, Redis). **Host Nginx** on the VPS owns ports 80/443 and reverse-proxies to the app’s **published localhost port** (e.g. `127.0.0.1:8000`).


Sample app: **Silo** on host port **8000**, container `silo_web_prod`.

---

## Architecture

```text
Internet
   │
   ▼
┌──────────────────────────────────────────┐
│  Host Nginx (systemd, ports 80/443)      │
│  /etc/nginx/conf.d/*.conf                │
│  TLS · domain routing · security headers │
└──────────────────────────────────────────┘
                 │
                 ▼  http://127.0.0.1:8000
┌──────────────────────────────────────────┐
│  Docker Compose stack                    │
│  web (127.0.0.1:8000→8000) · celery · db │
│  internal bridge — db/redis not public   │
└──────────────────────────────────────────┘
```

---

## Prerequisites

1. Fresh Ubuntu 22.04+ VPS with root or sudo access.
2. DNS A/AAAA for your domain pointing at this VPS.
3. SSH key access.

---

## Step 1: Core server hardening (one-time, as root)

See [`vps/README.md` — Step 1](vps/README.md) for SSH, `deploy` user, UFW, and passwordless sudo.

Install Docker Engine for the `deploy` user:

```bash
curl -fsSL https://get.docker.com | sh
usermod -aG docker deploy
```

---

## Step 2: Bootstrap host Nginx + Certbot

Run the VPS bootstrap script (installs **system Nginx**, not a Docker proxy):

```bash
git clone <YOUR_REPO_URL> /var/www/vps-deployment
cd /var/www/vps-deployment/vps
sudo ./setup-vps-environment.sh
```

This enables Nginx on 80/443, Certbot webroot at `/var/www/certbot`, and disables `sites-enabled/default`. Site configs go in **`/etc/nginx/conf.d/`**.

Verify:

```bash
systemctl is-active nginx
ls /var/www/certbot
```

---

## Step 3: Deploy the Docker app stack

Copy `templates/django-asgi/` into your app repo (or clone on the VPS). The blueprint publishes web **only on localhost**:

```yaml
ports:
  - "127.0.0.1:8000:8000"   # WEB_HOST_PORT in .env
```

On the VPS:

```bash
cd /var/www/silo   # your compose directory
docker compose up -d
docker ps
curl -s http://127.0.0.1:8000/ | head
```

**Do not** bind `0.0.0.0:8000` publicly — only host Nginx should face the internet.

Example Silo compose (`silo_web_prod`):

```yaml
web:
  container_name: silo_web_prod
  ports:
    - "127.0.0.1:8000:8000"
  # no gateway network required
```

---

## Step 4: Host Nginx → Docker port (`/etc/nginx/conf.d/`)

Templates: [`templates/django-asgi/nginx/`](templates/django-asgi/nginx/README.md)

### HTTP testing

```bash
sudo cp /var/www/vps-deployment/docker/templates/django-asgi/nginx/silo-docker-http.conf \
  /etc/nginx/conf.d/silo-api.conf
sudo vim /etc/nginx/conf.d/silo-api.conf
# CHANGE: server_name → api.example.com or your VPS IP
# CHANGE: proxy_pass port → 8000 (must match compose ports)

sudo nginx -t && sudo systemctl reload nginx
curl -s http://127.0.0.1:8000/ | head    # direct to container
curl -s http://127.0.0.1/ | head          # via Nginx
```

App `.env`:

```bash
ALLOWED_HOSTS=api.example.com,169.58.141.216,localhost
```

### HTTPS (production)

```bash
sudo certbot certonly --webroot -w /var/www/certbot -d api.example.com

sudo cp /var/www/vps-deployment/docker/templates/django-asgi/nginx/silo-docker.conf \
  /etc/nginx/conf.d/silo-api.conf
sudo vim /etc/nginx/conf.d/silo-api.conf
# CHANGE: domain + 127.0.0.1:8000

sudo nginx -t && sudo systemctl reload nginx
curl -I https://api.example.com
```

App `.env`:

```bash
ALLOWED_HOSTS=api.example.com
CSRF_TRUSTED_ORIGINS=https://api.example.com
```

---

## Step 5: Day-to-day lifecycle

| Action | Command |
|--------|---------|
| Pull and recreate app | `cd /var/www/silo && docker compose pull && docker compose up -d` |
| App logs | `docker compose logs -f web` |
| Reload host Nginx | `sudo nginx -t && sudo systemctl reload nginx` |
| Check published port | `ss -tlnp \| grep 8000` |

Wire CI: copy `templates/django-asgi/github-deploy.yml` to the app repo.

---

## Step 6: Remove an application

```bash
cd /var/www/silo
docker compose down -v
sudo rm -f /etc/nginx/conf.d/silo-api.conf
sudo nginx -t && sudo systemctl reload nginx
```

---

## Blueprint files

```text
docker/templates/django-asgi/
├── docker-compose.yml      # 127.0.0.1:8000 publish, internal network
├── Dockerfile
├── nginx/
│   ├── README.md
│   ├── silo-docker.conf    # host Nginx HTTPS → 127.0.0.1:port
│   └── silo-docker-http.conf
└── github-deploy.yml
```

---

## Operational notes

- **One edge**: system Nginx on 80/443 only — no Docker nginx on those ports.
- **Publish to localhost**: `127.0.0.1:<port>:8000` — never `0.0.0.0:8000` on a public VPS.
- **Nginx config**: `/etc/nginx/conf.d/` on the host (same layout as native VPS apps).
- **Multiple apps**: different host ports (`8001`, `8002`) and one `conf.d/*.conf` per domain.
- **No `gateway` network** needed for this layout.

---

## Legacy: containerized edge (`global-proxy`)

An older layout used a Docker `global-nginx` container + `gateway` network. That folder has been removed. Use **host Nginx + `127.0.0.1` ports** (this README) instead.
