# Native Nginx (host)

Site configs live in **`/etc/nginx/conf.d/`** — not `sites-available` / `sites-enabled`.

Copy a template from this folder, search for `CHANGE:` and replace example values, then reload Nginx.

| Template | Use |
|----------|-----|
| `silo-api.conf` | HTTPS + ACME + WebSockets → Unix socket |
| `silo-api-http.conf` | HTTP only for testing |

## What to change

| What | Example | Where it comes from |
|------|---------|---------------------|
| **Domain** | `api.example.com` | DNS A record → this VPS |
| **App name** | `silo` | `APP_NAME` — socket path `/var/www/silo/silo.sock` |
| **Socket** | `/var/www/silo/silo.sock` | Gunicorn bind in `systemd/silo-gunicorn.service` |

## Install (HTTPS)

```bash
sudo cp silo-api.conf /etc/nginx/conf.d/silo-api.conf
sudo vim /etc/nginx/conf.d/silo-api.conf   # edit CHANGE: lines
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

## Install (HTTP testing)

```bash
sudo cp silo-api-http.conf /etc/nginx/conf.d/silo-api.conf
sudo vim /etc/nginx/conf.d/silo-api.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

## Certbot

```bash
sudo certbot certonly --webroot -w /var/www/certbot -d api.example.com
# Then switch to silo-api.conf (HTTPS) if you started with HTTP-only
sudo nginx -t && sudo systemctl reload nginx
```
