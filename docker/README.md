# Docker architecture

Containerized deployment: **global Nginx** (TLS on 80/443) → **app containers** on the shared `gateway` Docker network. Postgres, Redis, and the app runtime live inside per-app Compose stacks.

Sample upstream container name: **app-web**. Adjust `container_name`, domains, and image names when copying the blueprint.

---

## Architecture

```text
Internet
   │
   ▼
┌──────────────────────────────────────────┐
│  global-nginx (Docker, ports 80/443)     │
│  TLS · domain routing · security headers │
└──────────────────────────────────────────┘
                 │
                 ▼  http://app-web:8000 on network `gateway`
┌──────────────────────────────────────────┐
│  App Compose stack (per application)     │
│  web · worker · beat · db · redis        │
│  internal bridge + gateway for web only  │
└──────────────────────────────────────────┘
```

---



## Prerequisites

1. Fresh Ubuntu 22.04+ VPS with root or sudo access.
2. DNS A/AAAA for your domain pointing at this VPS.
3. SSH key access (password login disabled before you finish hardening).

---



## Step 1: Core server hardening (one-time, as root)

Run on a fresh VPS before deploying the Docker stack.

### 1.1 Update the OS

```bash
apt update && apt upgrade -y
apt install -y curl ca-certificates gnupg ufw git
```



### 1.2 Create the `deploy` user (sudo + docker)

```bash
adduser --disabled-password --gecos "" deploy
usermod -aG sudo deploy
```

Install Docker Engine:

```bash
# https://docs.docker.com/engine/install/ubuntu/
curl -fsSL https://get.docker.com | sh
usermod -aG docker deploy
```

Allow passwordless sudo for `deploy` (required — `deploy` has no login password):

```bash
echo "deploy ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/deploy
chmod 440 /etc/sudoers.d/deploy
```

Create a new key on your **local machine** (or use an existing one):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/contabo-server -C "contabo-server"
cat ~/.ssh/contabo-server.pub
```

On the VPS **as root**, install the public key for `deploy`:

```bash
mkdir -p /home/deploy/.ssh
# Paste the public key into authorized_keys (vim, or echo 'ssh-ed25519 AAAA...' >> ...)
vim /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

Alternatively, copy root's existing keys:

```bash
cp /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
chown -R deploy:deploy /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
chmod 600 /home/deploy/.ssh/authorized_keys
```

Verify you can SSH as `deploy` from your machine **before** disabling root login:

```bash
ssh -i ~/.ssh/contabo-server deploy@YOUR_SERVER_IP
```



### 1.3 Harden SSH (`/etc/ssh/sshd_config`)

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



### 1.4 UFW firewall

As root (or `sudo` as `deploy`):

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



## Step 2: Shared Docker network and Certbot webroot

As `deploy` (or root):

```bash
sudo mkdir -p /var/www/certbot
sudo chown -R deploy:deploy /var/www/certbot
docker network create gateway
```

---



## Step 3: Clone repo and start the edge proxy

```bash
sudo mkdir -p /var/www && sudo chown deploy:deploy /var/www
git clone <YOUR_REPO_URL> /var/www/vps-deployment
cd /var/www/vps-deployment/docker/global-proxy
docker compose up -d
```

Verify:

```bash
docker ps --filter name=global-nginx
docker network inspect gateway
```

---



## Step 4: Onboard an application



### 4.1 App Compose stack

Copy `templates/django-asgi/` into your application repository (or deploy from a clone on the VPS):

- `docker-compose.yml` — web, worker, beat, Postgres, Redis
- `Dockerfile` — ASGI image build
- `.env` — secrets and image tags (never commit)

Ensure the `web` service joins the external `gateway` network and uses a stable `container_name` (default blueprint: `app-web`).

On the VPS:

```bash
cd /var/www/<your-app>
docker compose up -d
```



### 4.2 Nginx site for the domain

Copy and customize the proxy template:

```bash
cd /var/www/vps-deployment/docker/global-proxy
cp conf.d/templates/django-asgi.conf.template conf.d/api.example.com.conf
# Edit DOMAIN_NAME, CONTAINER_NAME, CONTAINER_PORT in the new file
```

For first-time TLS, start with HTTP-only + ACME in the template (or temporarily comment the HTTPS `server` block), then issue a certificate:

```bash
sudo certbot certonly --webroot -w /var/www/certbot -d api.example.com
```

Restore the full HTTPS config and reload:

```bash
./scripts/reload-nginx.sh
curl -I https://api.example.com
```

---



## Step 5: Day-to-day lifecycle


| Action                | Command                                                                       |
| --------------------- | ----------------------------------------------------------------------------- |
| Pull and recreate app | `cd /var/www/<app> && docker compose pull && docker compose up -d`            |
| App logs              | `docker compose logs -f web`                                                  |
| Reload edge Nginx     | `cd /var/www/vps-deployment/docker/global-proxy && ./scripts/reload-nginx.sh` |
| List gateway members  | `docker network inspect gateway --format '{{json .Containers}}'               |


Wire CI by copying `templates/django-asgi/github-deploy.yml` to the app repo as `.github/workflows/deploy.yml` and setting `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY`, `DEPLOY_PATH`.

---



## Step 6: Remove an application

```bash
cd /var/www/<your-app>
docker compose down -v   # omit -v to keep Postgres/Redis volumes
rm /var/www/vps-deployment/docker/global-proxy/conf.d/<domain>.conf
cd /var/www/vps-deployment/docker/global-proxy && ./scripts/reload-nginx.sh
```

---



## Blueprint files

```text
docker/
├── global-proxy/
│   ├── docker-compose.yml
│   ├── conf.d/templates/django-asgi.conf.template
│   └── scripts/reload-nginx.sh
└── templates/django-asgi/
    ├── docker-compose.yml
    ├── Dockerfile
    └── github-deploy.yml
```

---



## Operational notes

- Apps must **not** publish host ports 80/443; only `global-nginx` binds them.
- Live `conf.d/*.conf` on the VPS are gitignored — commit templates only.
- Use `container_name` in Compose so Nginx upstream hostnames stay stable across recreates.
- Do not run host Nginx on 80/443 on the same machine as `global-nginx`.

