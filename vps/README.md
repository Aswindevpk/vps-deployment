# VPS (native) architecture

Native Linux deployment: **Nginx** (TLS) → **Unix domain socket** → **Gunicorn + UvicornWorker** (ASGI/WebSockets), with **PostgreSQL**, **Redis**, and **Astral uv** for Python environments. No Docker required for the application runtime.

Sample app name throughout: **silo**. Rename paths, unit files, and sockets when copying the blueprint.

---

## Architecture

```text
Internet
   │
   ▼
┌──────────────────────────────────────────┐
│  Host Nginx (80/443)                     │
│  TLS · domain routing · security headers │
└──────────────────────────────────────────┘
                 │
                 ▼  unix:/var/www/silo/silo.sock
┌──────────────────────────────────────────┐
│  systemd: silo-gunicorn.service          │
│  Gunicorn -k uvicorn.workers.UvicornWorker│
│  User=deploy  Group=www-data             │
└──────────────────────────────────────────┘
        │                    │
        ▼                    ▼
  PostgreSQL (local)    Redis (local)
```

---

## Prerequisites

1. Fresh Ubuntu 22.04+ VPS with root or sudo access.
2. DNS A/AAAA for your domain pointing at this VPS.
3. SSH key access (password login disabled before you finish hardening).

---

## Step 1: Core server hardening (one-time, as root)

Run on a fresh VPS before the native stack. **Do not install Docker** on this path.

### 1.1 Update the OS

```bash
apt update && apt upgrade -y
apt install -y curl ca-certificates gnupg ufw git
```

### 1.2 Create the `deploy` user

```bash
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
```

Allow passwordless sudo for `deploy` (required — `deploy` has no login password):

```bash
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy
```

### 1.3 Copy root SSH keys to `deploy` and lock permissions

As root:

```bash
mkdir -p /home/deploy/.ssh
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

Verify you can SSH as `deploy` **before** disabling root login.

### 1.4 Harden SSH (`/etc/ssh/sshd_config`)

Run as **root** (SSH in as `root`, or `sudo -i` from `deploy` after passwordless sudo is configured). Editing `/etc/ssh/sshd_config` requires root; `sshd` is not on a normal user's `PATH` on Debian.

```bash
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
/usr/sbin/sshd -t && systemctl reload ssh
```

If you are already logged in as `deploy` with passwordless sudo:

```bash
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sudo /usr/sbin/sshd -t && sudo systemctl reload ssh
```

Confirm:

```bash
grep -E '^(PasswordAuthentication|PermitRootLogin|PubkeyAuthentication)' /etc/ssh/sshd_config
```

Expected:

```text
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

### 1.5 UFW firewall

As root (or `sudo` as `deploy`):

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status verbose
```

---

## Step 2: Bootstrap the host

Clone this repo and run the bootstrap script (installs Nginx, PostgreSQL, Redis, Certbot, and `uv`):

```bash
sudo mkdir -p /var/www && sudo chown deploy:deploy /var/www
git clone <YOUR_REPO_URL> /var/www/vps-deployment
cd /var/www/vps-deployment/vps
sudo chmod +x setup-vps-environment.sh
sudo ./setup-vps-environment.sh
```

This installs and enables Nginx, PostgreSQL, Redis (`redis-server`), Certbot, UFW rules (22/80/443), and Astral `uv` for the `deploy` user.

Verify:

```bash
systemctl is-active nginx postgresql redis-server
sudo -u deploy bash -lc 'uv --version'
```

---

## Step 3: Create the application silo

### 3.1 Application directory and code

```bash
sudo mkdir -p /var/www/silo
sudo chown deploy:www-data /var/www/silo
sudo -u deploy git clone <YOUR_APP_REPO_URL> /var/www/silo
cd /var/www/silo
```

Copy deploy helpers from this monorepo (optional but recommended):

```bash
cp /var/www/vps-deployment/vps/templates/django-asgi/deploy.sh /var/www/silo/
cp /var/www/vps-deployment/vps/templates/django-asgi/teardown.sh /tmp/silo-teardown.sh
chmod +x /var/www/silo/deploy.sh
```

### 3.2 PostgreSQL role and database

```bash
sudo -u postgres psql <<'SQL'
CREATE USER silo WITH PASSWORD 'change-me-strong';
CREATE DATABASE silo OWNER silo;
GRANT ALL PRIVILEGES ON DATABASE silo TO silo;
SQL
```

### 3.3 Application `.env`

```bash
sudo -u deploy tee /var/www/silo/.env >/dev/null <<'EOF'
DEBUG=0
SECRET_KEY=replace-with-long-random-string
ALLOWED_HOSTS=api.example.com
CSRF_TRUSTED_ORIGINS=https://api.example.com
DATABASE_URL=postgres://silo:change-me-strong@127.0.0.1:5432/silo
REDIS_URL=redis://127.0.0.1:6379/0
EOF
chmod 600 /var/www/silo/.env
```

### 3.4 Python environment (uv)

```bash
cd /var/www/silo
sudo -u deploy bash -lc 'export PATH="$HOME/.local/bin:$PATH"; cd /var/www/silo && uv sync --no-dev'
```

---

## Step 4: systemd unit

```bash
sudo cp /var/www/vps-deployment/vps/templates/django-asgi/systemd/silo-gunicorn.service \
  /etc/systemd/system/silo-gunicorn.service
sudo systemctl daemon-reload
sudo systemctl enable --now silo-gunicorn.service
sudo systemctl status silo-gunicorn.service
```

Confirm the socket exists and is group-readable by `www-data`:

```bash
ls -l /var/www/silo/silo.sock
# expect something like: srw-rw---- deploy www-data
```

---

## Step 5: Nginx site + TLS

### 5A. Temporary HTTP-only site (Certbot webroot)

Create `/etc/nginx/sites-available/silo-api.conf` with HTTP + ACME only (or temporarily comment out the HTTPS `server` block in the template). Example minimal HTTP server:

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name api.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 200 'waiting for TLS\n';
        add_header Content-Type text/plain;
    }
}
```

```bash
sudo ln -sf /etc/nginx/sites-available/silo-api.conf /etc/nginx/sites-enabled/silo-api.conf
# Disable default site if it conflicts:
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

### 5B. Issue certificate

```bash
sudo certbot certonly --webroot -w /var/www/certbot -d api.example.com
```

### 5C. Full HTTPS config from the template

```bash
sudo cp /var/www/vps-deployment/vps/templates/django-asgi/nginx/silo-api.conf \
  /etc/nginx/sites-available/silo-api.conf
# Edit server_name and certificate paths if your domain differs
sudo nginx -t && sudo systemctl reload nginx
curl -I https://api.example.com
```

Renewal hook (optional):

```bash
sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh >/dev/null <<'EOF'
#!/bin/sh
systemctl reload nginx
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

---

## Step 6: Day-to-day lifecycle

| Action | Command |
|--------|---------|
| Deploy / update code | `cd /var/www/silo && ./deploy.sh` |
| Restart app | `sudo systemctl restart silo-gunicorn` |
| App logs | `sudo journalctl -u silo-gunicorn -f` |
| Reload Nginx | `sudo nginx -t && sudo systemctl reload nginx` |
| Redis CLI | `redis-cli ping` |

Wire CI by copying `templates/django-asgi/github-deploy.yml` to the app repo as `.github/workflows/deploy.yml` and setting `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_PATH`.

---

## Step 7: Teardown

Removes systemd unit, Nginx site, app directory, and optionally Postgres DB/role and certificates:

```bash
sudo APP_NAME=silo APP_DOMAIN=api.example.com DROP_DATABASE=1 DELETE_CERTS=0 \
  /var/www/vps-deployment/vps/templates/django-asgi/teardown.sh
```

Set `DELETE_CERTS=1` only if you intend to revoke/remove the Let's Encrypt lineage for that domain.

---

## Blueprint files

```text
templates/django-asgi/
├── systemd/silo-gunicorn.service   # Gunicorn + UvicornWorker → silo.sock
├── nginx/silo-api.conf             # TLS + /ws/ + proxy to Unix socket
├── deploy.sh                       # git pull · uv sync · migrate · restart
├── github-deploy.yml               # SSH deploy workflow for the app repo
└── teardown.sh                     # Full app removal
```

---

## Operational notes

- **Socket permissions**: Service runs as `User=deploy` `Group=www-data` with `UMask=007` so Nginx can connect to `silo.sock`.
- **Do not** bind Gunicorn to a public TCP port in production when using this blueprint; prefer the Unix socket.
- Keep `.env` mode `600` and owned by `deploy`.
- For multiple apps on one host, duplicate the blueprint with unique `APP_NAME`, socket path, systemd unit, Nginx `server_name`, and Postgres database.
- Do not run Docker `global-nginx` on 80/443 on the same machine as host Nginx.
