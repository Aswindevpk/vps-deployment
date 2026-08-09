# vps-deployment

Single source of truth for VPS infrastructure. This monorepo supports **two** deployment paradigms:

| Path | Paradigm | When to use |
|------|----------|-------------|
| [`docker/`](docker/README.md) | Containerized Nginx edge proxy + app Compose stacks on a shared `gateway` network | Multiple isolated apps, portable deploys, GHCR images |
| [`vps/`](vps/README.md) | Native Nginx + systemd + Gunicorn/UvicornWorker + Postgres + Redis + `uv` | Maximum performance, Unix sockets, fewer moving parts on a single VPS |

```text
vps-deployment/
├── README.md                 # This file — overview and conventions
├── docker/                   # Containerized architecture (see docker/README.md)
│   ├── global-proxy/         # Shared edge Nginx (80/443 → apps)
│   └── templates/django-asgi/# App blueprint (Compose + Dockerfile + CI)
└── vps/                      # Native Linux architecture (see vps/README.md)
    ├── setup-vps-environment.sh
    └── templates/django-asgi/# systemd + Nginx socket + deploy/teardown
```

---

## Choose a paradigm

- **Docker**: One `global-nginx` container owns ports 80/443. Apps never publish public ports; they join the external Docker network `gateway` and are reached by `container_name`.
- **VPS (native)**: Host Nginx terminates TLS and proxies to a Unix domain socket (`/var/www/<app>/<app>.sock`) served by Gunicorn with `uvicorn.workers.UvicornWorker`. Postgres, Redis, and Certbot run as system services.

Do **not** run both edge proxies on the same VPS binding 80/443 at once. Pick one edge for a given host.

---

## Getting started

Initial VPS setup differs by paradigm — follow the README for the path you chose:

| Paradigm | Start here |
|----------|------------|
| Docker | [`docker/README.md`](docker/README.md) — deploy user, Docker Engine, `gateway` network, global proxy |
| VPS (native) | [`vps/README.md`](vps/README.md) — deploy user, host packages via `setup-vps-environment.sh` |

---

## Repository conventions

- **Secrets**: Never commit `.env` or live TLS private keys. Use `.env.example` as documentation only.
- **Host-specific Nginx sites**: Live `*.conf` under `docker/global-proxy/conf.d/` are gitignored; commit templates only.
- **App names**: VPS examples use `silo` as the sample project name — rename paths, unit files, and sockets when copying the blueprint.

---

## Quick reference

| Task | Docker | VPS (native) |
|------|--------|--------------|
| Full setup guide | [`docker/README.md`](docker/README.md) | [`vps/README.md`](vps/README.md) |
| Bootstrap host packages | Docker install + `gateway` network | `vps/setup-vps-environment.sh` |
| Edge proxy | `docker/global-proxy` | System Nginx site in `sites-available` |
| App process | Compose (`web` / Celery) | `systemd` unit (`silo-gunicorn.service`) |
| Upstream | `http://container:port` on `gateway` | `unix:/var/www/silo/silo.sock` |
| Reload proxy | `./scripts/reload-nginx.sh` | `sudo nginx -t && sudo systemctl reload nginx` |
| Remove app | `docker compose down` + delete conf | `teardown.sh` |
