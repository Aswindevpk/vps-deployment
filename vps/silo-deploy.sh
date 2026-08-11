PROJECT_DIR="/var/www/silo"
echo "🚀 Starting Deployment..."

cd $PROJECT_DIR

# 1. Force the system to recognize uv path binaries
export PATH="$HOME/.local/bin:$PATH"

# 1. Pull latest code from main branch
git pull origin main

# 2. Sync dependencies using uv
uv sync --frozen --group prod

# 3. Run database migrations
uv run python manage.py migrate --noinput

# 4. Clear and compile static files
uv run python manage.py collectstatic --noinput

# 5. Reload Gunicorn cleanly without dropping active connections
sudo systemctl restart silo-gunicorn

echo "✅ Deployment Successful!"