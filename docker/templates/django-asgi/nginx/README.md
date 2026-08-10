# Host Nginx for Docker apps

Edge TLS and routing use **system Nginx** on the VPS (`/etc/nginx/conf.d/`), not a Docker `global-nginx` container.

Docker apps publish the web port **only on localhost**:

```yaml
ports:
  - "127.0.0.1:8000:8000"
```

Host Nginx proxies to `http://127.0.0.1:8000` (or another host port per app).

| Template | Use |
|----------|-----|
| `silo-docker.conf` | HTTPS + WebSockets |
| `silo-docker-http.conf` | HTTP testing |

## What to change (`CHANGE:` in file)

| What | Example |
|------|---------|
| Domain | `api.example.com` |
| Host port | `8000` — matches compose `127.0.0.1:8000:8000` |

## HTTP testing

```bash
sudo cp silo-docker-http.conf /etc/nginx/conf.d/silo-api.conf
sudo vim /etc/nginx/conf.d/silo-api.conf
sudo nginx -t && sudo systemctl reload nginx
curl -s http://127.0.0.1:8000/ | head
curl -s http://127.0.0.1/ | head
```

## HTTPS

```bash
sudo certbot certonly --webroot -w /var/www/certbot -d api.example.com
sudo cp silo-docker.conf /etc/nginx/conf.d/silo-api.conf
sudo vim /etc/nginx/conf.d/silo-api.conf
sudo nginx -t && sudo systemctl reload nginx
```

## Multiple apps

Use a different host port per app (e.g. `8001`, `8002`) and a separate `conf.d/*.conf` per domain.
