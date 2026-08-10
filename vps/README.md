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
```

### 1.2 Create the `deploy` user

Create the new `deploy` user without a password (we will use SSH keys instead):

```bash
adduser --disabled-password --gecos "" deploy
```

Add the `deploy` user to the `sudo` group so it can run administrative commands:

```bash
usermod -aG sudo deploy
```

Allow passwordless sudo for `deploy` (required — `deploy` has no login password):

Create the sudoers rule to grant the permissions:

```bash
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
```

Lock down the permissions of the new sudoers file to prevent unauthorized edits:

```bash
chmod 440 /etc/sudoers.d/deploy
```

### 1.3 Copy root SSH keys to `deploy` and lock permissions

As root, copy the existing root keys to the `deploy` user and set permissions:

Create the SSH directory for the `deploy` user:

```bash
mkdir -p /home/deploy/.ssh
```

Copy the authorized keys from the `root` user to the new `deploy` user so you can log in:

```bash
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
```

Change the ownership of the SSH directory and its contents to the `deploy` user:

```bash
chown -R deploy:deploy /home/deploy/.ssh
```

Set strict permissions on the `.ssh` directory (only the owner can read/write/execute):

```bash
chmod 700 /home/deploy/.ssh
```

Set strict permissions on the `authorized_keys` file (only the owner can read/write):

```bash
chmod 600 /home/deploy/.ssh/authorized_keys
```

**Add your local SSH key**

If you don't already have an SSH key on your local machine, create a new one:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/<key_name> -C "<key_name>"
```

Copy the public key output from your local machine:

```bash
cat ~/.ssh/<key_name>.pub
```

Back on the server, open the `authorized_keys` file and paste the copied key:

```bash
vim /home/deploy/.ssh/authorized_keys
```

Verify you can SSH as `deploy` **before** disabling root login.

```bash
ssh -i ~/.ssh/<key_file_name> deploy@<YOUR_SERVER_IP>
```


### 1.4 Harden SSH (`/etc/ssh/sshd_config`)

This guide walks through locking down SSH access on a Linux server (Debian/Ubuntu) by editing `/etc/ssh/sshd_config` using the `vim` text editor.

---

#### 1. Overview of Changes

| Directive | Setting | Purpose |
| :--- | :--- | :--- |
| `PasswordAuthentication` | `no` | Blocks brute-force password attacks; forces SSH key logins. |
| `PermitRootLogin` | `no` | Prevents direct SSH logins as `root`; requires logging in as a standard user first. |
| `PubkeyAuthentication` | `yes` | Explicitly enables cryptographic SSH key pair logins. |

---

#### 2. Complete Step-by-Step Procedure

**Step 1: Open the configuration file in Vim**
```bash
sudo vim /etc/ssh/sshd_config
```

---

**Step 2: Search, edit, save, and exit in Vim**

1. **Disable Password Authentication:**
* Type `/PasswordAuthentication` and press `Enter`.
* Press `i` to enter Insert mode.
* Edit (and uncomment by removing `#` if present) to match:
```text
PasswordAuthentication no
```
* Press `Esc`.

2. **Disable Root Login:**
* Type `/PermitRootLogin` and press `Enter`.
* Press `i` to enter Insert mode.
* Edit to match:
```text
PermitRootLogin no
```
* Press `Esc`.

3. **Enable Public Key Authentication:**
* Type `/PubkeyAuthentication` and press `Enter`.
* Press `i` to enter Insert mode.
* Edit to match:
```text
PubkeyAuthentication yes
```
* Press `Esc`.

4. **Save and Exit:**
* Type `:wq` and press `Enter`.

---

**Step 3: Test syntax and apply changes**

Run these commands in your shell:

```bash
# Test the configuration file for syntax errors (returns nothing if valid)
sudo /usr/sbin/sshd -t

# Reload the SSH daemon to apply changes
sudo systemctl reload ssh
```

---

#### 3. Verification & Testing

**Step 1: Verify the file settings**

Run this command to print the updated configuration values:

```bash
sudo grep -E '^(PasswordAuthentication|PermitRootLogin|PubkeyAuthentication)' /etc/ssh/sshd_config
```

**Expected Output:**

```text
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

**Step 2: Test connection before exiting**

Do **not** close your current terminal window. Open a **new, separate terminal window** and test logging in:

```bash
ssh -i ~/.ssh/<key_file_name> deploy@<YOUR_SERVER_IP>
```

If you log in successfully via your SSH key, the lockdown is complete and working safely.

### 1.5 UFW firewall

As root (or `sudo` as `deploy`):

**install ufw** if not installed
```bash
sudo apt install ufw -y
```

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status verbose
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

## Step 5: Nginx (`/etc/nginx/conf.d/`)

First, ensure Nginx is installed:

```bash
sudo apt install nginx
```

**Configure Nginx to use `conf.d` exclusively:**

By default, Ubuntu/Debian's Nginx configuration includes `sites-enabled`. To strictly use the `conf.d` directory for our setups, we should disable the `sites-enabled` include.

Open the main Nginx config file:

```bash
sudo vim /etc/nginx/nginx.conf
```

Find the line that includes `sites-enabled` and comment it out by adding a `#` at the beginning:

```text
# include /etc/nginx/sites-enabled/*;
```

Save and exit.

**Key Nginx Directories:**
- `/etc/nginx` - Main configuration directory.
- `/var/www/html` - Default website directory.

**Testing & Reloading Configuration:**

Before applying changes, test your configuration for syntax errors:

```bash
sudo nginx -t 
```

If you need to find an issue and the standard test doesn't provide enough detail, print the full configuration to inspect it:

```bash
sudo nginx -T
```

To apply changes without downtime (restarting causes downtime), you should safely reload Nginx:

```bash
sudo systemctl reload nginx
```

create new conf file in conf.d for your domain

```bash
sudo vim /etc/nginx/conf.d/silo-api.aswindev.in.conf
```

refer nginx template folder for templates

## Step 6: SSL Certificate - HTTPS

Create an SSL certificate for your domain:

```bash
sudo apt install certbot python3-certbot-nginx -y
```

Generate the certificate and let Certbot automatically edit your Nginx configuration:

```bash
sudo certbot --nginx -d dev.aswindev.in
```

Test automatic renewal:

```bash
sudo certbot renew --dry-run
```

---

## Step 7: Day-to-day lifecycle

| Action | Command |
|--------|---------|
| Deploy / update code | `cd /var/www/silo && ./deploy.sh` |
| Restart app | `sudo systemctl restart silo-gunicorn` |
| App logs | `sudo journalctl -u silo-gunicorn -f` |
| Reload Nginx | `sudo nginx -t && sudo systemctl reload nginx` |
| Redis CLI | `redis-cli ping` |

Wire CI by copying `templates/django-asgi/github-deploy.yml` to the app repo as `.github/workflows/deploy.yml` and setting `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_PATH`.

---

## Step 8: Teardown

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
├── nginx/
│   ├── README.md                   # conf.d install guide
│   ├── silo-api.conf               # HTTPS → Unix socket
│   └── silo-api-http.conf          # HTTP testing → Unix socket
├── systemd/silo-gunicorn.service   # Gunicorn + UvicornWorker → silo.sock
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
- For Docker apps on the same host, see [`docker/README.md`](docker/README.md) — host Nginx proxies to `127.0.0.1` published ports.
