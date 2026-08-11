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

## Step 3: Deploy Django in VPS

Go to www dir and create project directory:
```bash
cd /var/www   
sudo mkdir pixel
```

If permission errors give whole folder permission to the existing current user:
```bash
sudo chown -R deploy:deploy /var/www/pixel
sudo chmod -R 755 /var/www/pixel
```

Git clone:
```bash
git clone https://github.com/Aswindevpk/pixel-django.git .
```

Install uv (If using uv install all packages for production I defined it prod):
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.bashrc
```

Setup env before run:
```bash
sudo vim .env
```

Run uv:
```bash
uv sync --frozen --group prod
uv run python manage.py 
uv run python manage.py createsuperuser
uv run python manage.py collectstatic --no-input
uv run gunicorn config.wsgi:application --bind 0.0.0.0:8000
```
Make sure gunicorn runs without errors.

---

## Step 4: Setup gunicorn unix socket

Create a service file:
```bash
cd /etc/systemd/system/
sudo vim pixel-gunicorn.service
```

Service file content:
```ini
[Unit]
Description=Gunicorn instance for Pixel
After=network.target

[Service]
User=deploy
Group=www-data
WorkingDirectory=/var/www/pixel
ExecStart=/var/www/pixel/.venv/bin/gunicorn \
          --access-logfile - \
          --workers 3 \
          --bind unix:/var/www/pixel/pixel.sock \
          config.wsgi:application
[Install]
WantedBy=multi-user.target
```

Enable and start gunicorn server:
```bash
sudo systemctl daemon-reload 
sudo systemctl enable pixel-gunicorn 
sudo systemctl start pixel-gunicorn
```
`pixel.sock` file will be created in `/var/www/pixel`.

If any issue run for status and log:
```bash
sudo systemctl status pixel-gunicorn
sudo journalctl -u pixel-gunicorn.service --no-pager | tail -n 20
```

---

## Step 5: Nginx configuration

```bash
sudo apt install nginx
cd /etc/nginx/conf.d
```

Create and config file in your domain name:
```bash
sudo vim pixel.aswindev.in.conf
```

File content of configuration:
```nginx
server {
    server_name pixel.aswindev.in;

    # Global Security Headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Frame-Options "DENY" always;
    #add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:;" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=()" always;

    # Serve Django Static Files directly via Nginx
    location /static/ {
            alias /var/www/pixel/static/;
    }
    # Serve Django Static Files directly via Nginx
    location /media/ {
            alias /var/www/pixel/media/;
    }

    location / {
        include proxy_params;
        proxy_pass http://unix:/var/www/pixel/pixel.sock;

        # CRITICAL FIX: Force HTTP/1.1 to preserve the Host header
        proxy_http_version 1.1;
    }
}
```

Test if the configuration is correct or not:
```bash
sudo nginx -t
sudo systemctl reload nginx
sudo nginx -T # to get current configuration 
```

---

## Step 6: SSL Certificate - HTTPS

Create ssl certificate for domain:
```bash
sudo apt install certbot python3-certbot-nginx -y
```

Generate certificate and edit nginx configuration:
```bash
sudo certbot --nginx -d pixel.aswindev.in
```

Automatic renewal:
```bash
sudo certbot renew --dry-run
```

Add the A record in the DNS pointing to the vps IP Address.

Restart services to apply everything:
```bash
sudo systemctl restart pixel-gunicorn
sudo systemctl reload nginx
```

---

## Step 7: Day-to-day lifecycle

| Action | Command |
|--------|---------|
| Restart app | `sudo systemctl restart pixel-gunicorn` |
| App logs | `sudo journalctl -u pixel-gunicorn -f` |
| Reload Nginx | `sudo nginx -t && sudo systemctl reload nginx` |

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
