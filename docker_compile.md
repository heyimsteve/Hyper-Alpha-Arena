# Docker Compilation Guide

This guide outlines the process of compiling your development changes back into Docker for production-like deployment.

## Prerequisites

- All development changes committed or staged in git
- Docker and Docker Compose installed
- Local PostgreSQL running with latest data
- Backend and frontend development servers stopped

## Step 1: Prepare for Docker Build

### 1.1 Stop Development Servers

```bash
# Stop backend (Ctrl+C in Terminal 1)
# Stop frontend (Ctrl+C in Terminal 2)

# Or find and kill processes
lsof -ti:8802 | xargs kill -9  # Backend
lsof -ti:5173 | xargs kill -9  # Frontend
```

### 1.2 Review Changes

```bash
# Check what has changed
git status

# Review uncommitted changes
git diff

# Optionally commit your work
git add .
git commit -m "Development changes before Docker compilation"
```

## Step 2: Export Local Database (Optional but Recommended)

If you made database changes during development, export them to preserve your work.

### 2.1 Export Local Databases

```bash
# Export main database
pg_dump -U alpha_user -d alpha_arena -F c -f ./alpha_arena_local.dump

# Export snapshots database
pg_dump -U alpha_user -d alpha_snapshots -F c -f ./alpha_snapshots_local.dump

# OR as SQL
pg_dump -U alpha_user -d alpha_arena > ./alpha_arena_local.sql
pg_dump -U alpha_user -d alpha_snapshots > ./alpha_snapshots_local.sql
```

### 2.2 Backup Encryption Key

```bash
# Ensure encryption key is backed up
cp ./data/.encryption_key ./.encryption_key.backup
```

## Step 3: Clean Up Development Environment Files

### 3.1 Remove Development .env Files

```bash
# Backup first
cp backend/.env backend/.env.backup
cp frontend/.env.local frontend/.env.local.backup

# Remove (Docker will use environment variables from docker-compose.yml)
rm -f backend/.env
rm -f frontend/.env.local
```

### 3.2 Remove any Development-Only Changes to main.py

If you added encryption key loading code to `backend/main.py` for local development, you may want to remove or adjust it since Docker handles this differently.

**Review `backend/main.py`** - the Docker CMD in Dockerfile handles encryption key loading, so local file loading code can be removed or made conditional:

```python
import os
from pathlib import Path

def load_encryption_key():
    """Load encryption key - used in local dev, Docker sets via environment"""
    # Check if already set by Docker
    if "HYPERLIQUID_ENCRYPTION_KEY" in os.environ:
        return os.environ["HYPERLIQUID_ENCRYPTION_KEY"]
    
    # Local development: load from file
    key_file = os.environ.get("HYPERLIQUID_ENCRYPTION_KEY_FILE", "../data/.encryption_key")
    key_path = Path(__file__).parent.parent / key_file.lstrip("../")
    
    if key_path.exists():
        with open(key_path, "r") as f:
            key = f.read().strip()
            os.environ["HYPERLIQUID_ENCRYPTION_KEY"] = key
            return key
    
    # Generate new if not exists
    from cryptography.fernet import Fernet
    key = Fernet.generate_key().decode()
    key_path.parent.mkdir(parents=True, exist_ok=True)
    with open(key_path, "w") as f:
        f.write(key)
    os.environ["HYPERLIQUID_ENCRYPTION_KEY"] = key
    return key

load_encryption_key()
```

## Step 4: Build Docker Images

### 4.1 Clean Previous Docker Build

```bash
# Remove old images to force fresh build
docker-compose down
docker rmi hyper-alpha-arena-app:latest 2>/dev/null || true

# OR more aggressive clean (removes all unused images)
docker system prune -a --volumes
```

### 4.2 Build Fresh Images

```bash
# Build without cache to ensure all changes are included
docker-compose build --no-cache

# OR build with cache (faster, but may miss changes)
docker-compose build
```

**Expected output**: You should see the frontend being built, followed by backend setup.

### 4.3 Verify Build

```bash
# List images
docker images | grep hyper-alpha-arena

# Should show newly built image with recent timestamp
```

## Step 5: Import Data into Docker PostgreSQL

### 5.1 Start Only PostgreSQL Container

```bash
# Start only database
docker-compose up -d postgres

# Wait for health check
docker-compose ps postgres

# Should show "healthy" status
```

### 5.2 Import Your Local Data

**If you have fresh data from local development:**

```bash
# Copy dump file into container
docker cp ./alpha_arena_local.dump hyper-arena-postgres:/tmp/alpha_arena.dump
docker cp ./alpha_snapshots_local.dump hyper-arena-postgres:/tmp/alpha_snapshots.dump

# Import into Docker PostgreSQL
docker exec hyper-arena-postgres pg_restore -U alpha_user -d alpha_arena -c -v /tmp/alpha_arena.dump
docker exec hyper-arena-postgres pg_restore -U alpha_user -d alpha_snapshots -c -v /tmp/alpha_snapshots.dump
```

**If using SQL format:**

```bash
# Copy SQL files
docker cp ./alpha_arena_local.sql hyper-arena-postgres:/tmp/alpha_arena.sql
docker cp ./alpha_snapshots_local.sql hyper-arena-postgres:/tmp/alpha_snapshots.sql

# Import
docker exec hyper-arena-postgres psql -U alpha_user -d alpha_arena -f /tmp/alpha_arena.sql
docker exec hyper-arena-postgres psql -U alpha_user -d alpha_snapshots -f /tmp/alpha_snapshots.sql
```

**Alternative: Let Docker initialize fresh databases:**

If you want to start fresh or your local changes are in migration scripts:

```bash
# Docker will auto-initialize on first run
# Skip import and let the app run migrations
```

### 5.3 Verify Data Import

```bash
# Check tables in main database
docker exec hyper-arena-postgres psql -U alpha_user -d alpha_arena -c "\dt"

# Check tables in snapshots database
docker exec hyper-arena-postgres psql -U alpha_user -d alpha_snapshots -c "\dt"

# Check row counts
docker exec hyper-arena-postgres psql -U alpha_user -d alpha_arena -c "SELECT COUNT(*) FROM users;"
```

## Step 6: Restore Encryption Key to Docker Volume

### 6.1 Start App Container Temporarily

```bash
# Start app to create volume
docker-compose up -d app

# Wait a few seconds for container to initialize
sleep 10
```

### 6.2 Copy Encryption Key

```bash
# Copy encryption key into Docker volume
docker cp ./data/.encryption_key hyper-arena-app:/app/data/.encryption_key

# Verify
docker exec hyper-arena-app cat /app/data/.encryption_key
```

### 6.3 Restart App Container

```bash
# Restart to load the encryption key
docker-compose restart app

# Or recreate
docker-compose up -d --force-recreate app
```

## Step 7: Start Full Application

### 7.1 Start All Services

```bash
# Stop any partial services
docker-compose down

# Start everything
docker-compose up -d

# Watch logs
docker-compose logs -f
```

### 7.2 Verify Health

```bash
# Check container status
docker-compose ps

# Should show both services as "healthy" or "running"

# Check application health
curl http://localhost:8802/api/health

# Should return: {"status":"healthy"}
```

### 7.3 Access Application

- **Application**: http://localhost:8802
- **API Docs**: http://localhost:8802/docs
- **Health Check**: http://localhost:8802/api/health

## Step 8: Verify Everything Works

### 8.1 Test Frontend

1. Open http://localhost:8802 in browser
2. Check that UI loads correctly
3. Verify data is displayed
4. Test navigation and interactions

### 8.2 Test Backend

```bash
# Test API endpoints
curl http://localhost:8802/api/health
curl http://localhost:8802/api/config/global

# Check WebSocket (if applicable)
# Use browser console or wscat tool
```

### 8.3 Check Logs

```bash
# App logs
docker-compose logs app

# Database logs
docker-compose logs postgres

# Follow logs in real-time
docker-compose logs -f app
```

## Step 9: Clean Up (Optional)

### 9.1 Remove Development Database Dumps

```bash
# Remove local dumps (keep backups if needed)
rm -f alpha_arena_local.dump alpha_snapshots_local.dump
rm -f alpha_arena_local.sql alpha_snapshots_local.sql

# Keep original Docker exports as backup
# rm -f alpha_arena.dump alpha_snapshots.dump
```

### 9.2 Stop Local PostgreSQL

```bash
# If you no longer need local PostgreSQL running
brew services stop postgresql@14
```

## Common Issues and Solutions

### Frontend Not Building

**Problem**: Build fails during frontend compilation

```bash
# Check frontend builds locally first
cd frontend
pnpm install
pnpm build

# If successful, rebuild Docker
docker-compose build --no-cache
```

### Backend Dependencies Missing

**Problem**: Python dependencies fail to install

```bash
# Verify pyproject.toml is correct
cat backend/pyproject.toml

# Try building backend separately
cd backend
pip install -e .

# If successful, rebuild Docker
```

### Database Connection Errors

**Problem**: App can't connect to database

```bash
# Check database is running
docker-compose ps postgres

# Check connection from app container
docker exec hyper-arena-app ping postgres

# Check DATABASE_URL in docker-compose.yml
# Should be: postgresql://alpha_user:alpha_pass@postgres:5432/alpha_arena
```

### Encryption Key Not Loading

**Problem**: Encrypted data can't be decrypted

```bash
# Verify key exists in volume
docker exec hyper-arena-app cat /app/data/.encryption_key

# Copy again if missing
docker cp ./data/.encryption_key hyper-arena-app:/app/data/.encryption_key

# Restart
docker-compose restart app
```

### Port Conflicts

**Problem**: Port 8802 or 5432 already in use

```bash
# Check what's using the port
lsof -ti:8802
lsof -ti:5432

# Stop conflicting service
# For backend dev server: pkill -f uvicorn
# For local postgres: brew services stop postgresql@14

# Or change port in docker-compose.yml
```

### Static Files Not Found

**Problem**: Frontend returns 404 or shows "Frontend not built yet"

```bash
# Verify frontend was built into image
docker exec hyper-arena-app ls -la /app/backend/static/

# Should show index.html and assets/

# If empty, rebuild with --no-cache
docker-compose build --no-cache app
```

## Docker Commands Reference

### View Logs

```bash
# All logs
docker-compose logs

# Specific service
docker-compose logs app
docker-compose logs postgres

# Follow logs
docker-compose logs -f app

# Last 100 lines
docker-compose logs --tail=100 app
```

### Restart Services

```bash
# Restart all
docker-compose restart

# Restart specific service
docker-compose restart app
docker-compose restart postgres

# Recreate containers (reload docker-compose.yml changes)
docker-compose up -d --force-recreate
```

### Access Containers

```bash
# Shell into app container
docker exec -it hyper-arena-app bash

# Shell into database container
docker exec -it hyper-arena-postgres bash

# Run psql in database
docker exec -it hyper-arena-postgres psql -U alpha_user -d alpha_arena
```

### Clean Up

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (DELETES DATA!)
docker-compose down -v

# Remove unused images
docker image prune -a

# Full cleanup (CAUTION!)
docker system prune -a --volumes
```

## Production Deployment Notes

### Environment Variables

For production, set these in `docker-compose.yml` or `.env`:

- Database credentials
- API keys
- Secret keys
- Environment-specific URLs

### Volume Backups

```bash
# Backup database volume
docker run --rm -v hyper-alpha-arena_postgres_data:/data -v $(pwd):/backup alpine tar czf /backup/postgres_backup.tar.gz /data

# Backup app data volume
docker run --rm -v hyper-alpha-arena_app_data:/data -v $(pwd):/backup alpine tar czf /backup/app_data_backup.tar.gz /data
```

### Health Monitoring

```bash
# Check health status
docker-compose ps

# Set up alerts for container failures
# Use tools like Prometheus, Grafana, or cloud monitoring
```

## Next Steps

- Set up CI/CD for automated builds
- Configure proper logging and monitoring
- Set up database backups
- Configure reverse proxy (nginx/traefik)
- Set up SSL/TLS certificates
- Configure production environment variables

## Returning to Local Development

When you need to go back to local development, see [`docker_separate.md`](./docker_separate.md).

**Quick workflow:**

1. Export Docker database: `docker exec hyper-arena-postgres pg_dump...`
2. Import to local: `pg_restore -U alpha_user...`
3. Start dev servers: `uvicorn main:app --reload` and `pnpm dev`
