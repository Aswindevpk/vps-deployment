# vps-deployment

Single source of truth for VPS infrastructure. Two deployment paradigms:

| Path | Paradigm | When to use |
|------|----------|-------------|
| [`docker/`](docker/README.md) | Docker app stacks + **host Nginx** → `127.0.0.1` published ports | Containerized apps, GHCR images, Postgres/Redis in Docker |
| [`vps/`](vps/README.md) | **Host Nginx** → Unix socket + systemd Gunicorn + host Postgres/Redis | No Docker for the app runtime; maximum socket performance |

Both use **system Nginx** on 80/443 (`/etc/nginx/conf.d/`). Neither uses a Docker nginx container by default.

```text
vps-deployment/
├── README.md
├── docker/                   # Compose blueprints + host Nginx templates for Docker apps
│   └── templates/django-asgi/
└── vps/                      # Bootstrap script + native app templates
    ├── setup-vps-environment.sh
    └── templates/django-asgi/
```

---

## Choose a paradigm

- **Docker apps**: Compose runs web/celery/db/redis. Web publishes `127.0.0.1:8000:8000`. Host Nginx proxies to that port.
- **Native VPS**: Gunicorn on a Unix socket. Host Nginx proxies to `unix:/var/www/silo/silo.sock`. Postgres/Redis on the host.

Use **one** Nginx edge on the VPS (system Nginx). Do not run `global-nginx` in Docker alongside it.

---

## Getting started

| Paradigm | Start here |
|----------|------------|
| Docker apps | [`docker/README.md`](docker/README.md) — Docker Engine + `vps/setup-vps-environment.sh` + Compose |
| Native VPS | [`vps/README.md`](vps/README.md) — `setup-vps-environment.sh` + systemd |

---

## Repository conventions

- **Secrets**: Never commit `.env` or TLS private keys.
- **Nginx sites**: `/etc/nginx/conf.d/` on the VPS host (templates in each `templates/django-asgi/nginx/`).
- **App names**: Examples use **silo** / `silo_web_prod` / port **8000**.

---

## Quick reference

| Task | Docker apps | Native VPS |
|------|-------------|------------|
| Full guide | [`docker/README.md`](docker/README.md) | [`vps/README.md`](vps/README.md) |
| Bootstrap host | `vps/setup-vps-environment.sh` + Docker install | `vps/setup-vps-environment.sh` |
| Edge proxy | `/etc/nginx/conf.d/` | `/etc/nginx/conf.d/` |
| App runtime | Docker Compose | systemd + Gunicorn |
| Nginx upstream | `http://127.0.0.1:8000` | `unix:/var/www/silo/silo.sock` |
| Reload Nginx | `sudo nginx -t && sudo systemctl reload nginx` | same |
