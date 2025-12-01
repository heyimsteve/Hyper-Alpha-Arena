# Docker Development Workflow - Quick Reference

This document provides a quick reference for switching between Docker and local development environments.

## 🎯 Quick Start

### Option 1: Automated Setup (Recommended)

**Separate from Docker:**
```bash
./setup_local_dev.sh
```

**Compile back to Docker:**
```bash
./compile_to_docker.sh
```

### Option 2: Manual Setup

See detailed guides:
- [`docker_separate.md`](./docker_separate.md) - Full separation guide
- [`docker_compile.md`](./docker_compile.md) - Full compilation guide

## 📋 Database Credentials

All environments use the same credentials for consistency:

```
User:     alpha_user
Password: alpha_pass
Databases:
  - alpha_arena      (main database)
  - alpha_snapshots  (snapshots)
```

**Docker:** `postgresql://alpha_user:alpha_pass@postgres:5432/alpha_arena`  
**Local:**  `postgresql://alpha_user:alpha_pass@localhost:5432/alpha_arena`

## 🔄 Common Workflows

### Starting Local Development

```bash
# Terminal 1: Backend
cd backend
uvicorn main:app --reload --host 0.0.0.0 --port 8802

# Terminal 2: Frontend
cd frontend
pnpm dev
```

**Access:**
- Frontend: http://localhost:5173
- Backend API: http://localhost:8802
- API Docs: http://localhost:8802/docs

### Starting Docker Environment

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Stop all services
docker-compose down
```

**Access:**
- Application: http://localhost:8802
- API Docs: http://localhost:8802/docs

## 💾 Database Operations

### Export from Docker

```bash
# Export databases
docker exec hyper-arena-postgres pg_dump -U alpha_user -d alpha_arena > alpha_arena.sql
docker exec hyper-arena-postgres pg_dump -U alpha_user -d alpha_snapshots > alpha_snapshots.sql

# Export encryption key
docker cp hyper-arena-app:/app/data/.encryption_key ./data/.encryption_key
```

### Import to Local

```bash
# Import databases
psql -U alpha_user -d alpha_arena < alpha_arena.sql
psql -U alpha_user -d alpha_snapshots < alpha_snapshots.sql
```

### Export from Local

```bash
# Export databases
pg_dump -U alpha_user -d alpha_arena > alpha_arena_local.sql
pg_dump -U alpha_user -d alpha_snapshots > alpha_snapshots_local.sql
```

### Import to Docker

```bash
# Copy SQL files
docker cp alpha_arena_local.sql hyper-arena-postgres:/tmp/alpha_arena.sql
docker cp alpha_snapshots_local.sql hyper-arena-postgres:/tmp/alpha_snapshots.sql

# Import
docker exec hyper-arena-postgres psql -U alpha_user -d alpha_arena -f /tmp/alpha_arena.sql
docker exec hyper-arena-postgres psql -U alpha_user -d alpha_snapshots -f /tmp/alpha_snapshots.sql
```

## 🔧 Troubleshooting

### Port Already in Use

```bash
# Kill process on port 8802
lsof -ti:8802 | xargs kill -9

# Kill process on port 5173
lsof -ti:5173 | xargs kill -9

# Kill process on port 5432
lsof -ti:5432 | xargs kill -9
```

### Local PostgreSQL Not Running

```bash
# Start PostgreSQL
brew services start postgresql@14

# Check status
brew services list

# Verify connection
psql -U alpha_user -d alpha_arena -c "SELECT 1;"
```

### Docker Container Issues

```bash
# Check status
docker-compose ps

# View logs
docker-compose logs app
docker-compose logs postgres

# Restart specific service
docker-compose restart app

# Recreate containers
docker-compose up -d --force-recreate

# Clean build
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Encryption Key Issues

```bash
# Local: Verify key exists
cat data/.encryption_key

# Docker: Verify key exists
docker exec hyper-arena-app cat /app/data/.encryption_key

# Regenerate (CAUTION: Invalidates encrypted data)
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" > data/.encryption_key
```

## 📁 Environment Files

### Backend (.env)

**Local development** (`backend/.env`):
```env
DATABASE_URL=postgresql://alpha_user:alpha_pass@localhost:5432/alpha_arena
SNAPSHOT_DATABASE_URL=postgresql://alpha_user:alpha_pass@localhost:5432/alpha_snapshots
HYPERLIQUID_ENCRYPTION_KEY_FILE=../data/.encryption_key
```

**Docker** (defined in `docker-compose.yml`):
```yaml
DATABASE_URL: postgresql://alpha_user:alpha_pass@postgres:5432/alpha_arena
SNAPSHOT_DATABASE_URL: postgresql://alpha_user:alpha_pass@postgres:5432/alpha_snapshots
```

### Frontend (.env.local)

**Local development** (`frontend/.env.local`):
```env
VITE_API_URL=http://localhost:8802
```

**Docker**: Not needed (frontend is compiled and served by backend)

## 🚀 Development Tips

### Backend Hot Reload

- Changes to any `.py` file trigger automatic reload
- No need to restart server manually
- Watch the terminal for reload confirmation

### Frontend Hot Reload

- Changes to any frontend file trigger instant browser update
- No need to refresh browser manually
- Check browser console for any errors

### Database Changes

**Local:**
```bash
# Connect to database
psql -U alpha_user -d alpha_arena

# Run migrations
cd backend
python database/init_hyperliquid_tables.py
```

**Docker:**
```bash
# Connect to database
docker exec -it hyper-arena-postgres psql -U alpha_user -d alpha_arena

# Run migrations (inside container)
docker exec hyper-arena-app python database/init_hyperliquid_tables.py
```

## 🎨 IDE Configuration

### VS Code

**.vscode/launch.json** (Backend debugging):
```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Backend",
      "type": "python",
      "request": "launch",
      "module": "uvicorn",
      "args": ["main:app", "--reload", "--host", "0.0.0.0", "--port", "8802"],
      "cwd": "${workspaceFolder}/backend",
      "env": {
        "DATABASE_URL": "postgresql://alpha_user:alpha_pass@localhost:5432/alpha_arena"
      }
    }
  ]
}
```

### Database Tools

**pgAdmin / TablePlus / DBeaver:**
- Host: localhost (local) or 127.0.0.1 (Docker)
- Port: 5432
- User: alpha_user
- Password: alpha_pass
- Database: alpha_arena

## 📊 Performance Comparison

| Aspect | Local Development | Docker |
|--------|------------------|--------|
| **Startup Time** | ~2 seconds | ~30 seconds |
| **Hot Reload** | Instant | Not available* |
| **Build Time** | N/A | ~5 minutes |
| **Debugging** | Easy | Moderate |
| **Production Parity** | Low | High |

*Docker has volume mounts for backend hot reload, but frontend requires rebuild

## 🔐 Security Notes

- Never commit `.env` files to git
- Keep encryption key secure (`.encryption_key`)
- Use different credentials for production
- Backup database before major changes

## 📚 File Structure

```
Hyper-Alpha-Arena/
├── backend/
│   ├── .env                    # Local dev config (gitignored)
│   └── ...
├── frontend/
│   ├── .env.local              # Local dev config (gitignored)
│   └── ...
├── data/
│   └── .encryption_key         # Encryption key (gitignored)
├── docker-compose.yml          # Docker configuration
├── Dockerfile                  # Docker build instructions
├── docker_separate.md          # Detailed separation guide
├── docker_compile.md           # Detailed compilation guide
├── DOCKER_QUICKREF.md          # This file
├── setup_local_dev.sh          # Automated setup script
└── compile_to_docker.sh        # Automated compilation script
```

## 🎯 Decision Guide

**Use Local Development when:**
- Actively developing features
- Debugging issues
- Testing changes frequently
- Need fast iteration

**Use Docker when:**
- Testing production behavior
- Deploying to server
- Sharing with team
- Need consistent environment

## 📞 Help

For detailed instructions:
- Separation: See [`docker_separate.md`](./docker_separate.md)
- Compilation: See [`docker_compile.md`](./docker_compile.md)

For issues, check logs:
- Local Backend: Terminal where uvicorn is running
- Local Frontend: Terminal where vite is running + browser console
- Docker: `docker-compose logs -f`
