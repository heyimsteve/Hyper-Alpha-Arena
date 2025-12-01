# Docker Separation Guide

This guide outlines the process of separating your development environment from Docker to enable faster iteration with hot-reload capabilities.

## Prerequisites

- PostgreSQL 14+ installed on macOS (verify with `postgres --version`)
- Python 3.12 installed
- Node.js 18+ and pnpm installed
- Git (to manage changes)

## Step 1: Export Current Docker Database

### 1.1 Ensure Docker is Running

```bash
docker-compose up -d postgres
```

### 1.2 Export Databases

Export both databases (main and snapshots):

```bash
# Export main database
docker exec hyper-arena-postgres pg_dump -U alpha_user -d alpha_arena -F c -f /tmp/alpha_arena.dump

# Copy to host
docker cp hyper-arena-postgres:/tmp/alpha_arena.dump ./alpha_arena.dump

# Export snapshots database
docker exec hyper-arena-postgres pg_dump -U alpha_user -d alpha_snapshots -F c -f /tmp/alpha_snapshots.dump

# Copy to host
docker cp hyper-arena-postgres:/tmp/alpha_snapshots.dump ./alpha_snapshots.dump
```

**Alternative: Plain SQL export (easier to inspect/edit)**

```bash
# Export main database as SQL
docker exec hyper-arena-postgres pg_dump -U alpha_user -d alpha_arena > ./alpha_arena.sql

# Export snapshots database as SQL
docker exec hyper-arena-postgres pg_dump -U alpha_user -d alpha_snapshots > ./alpha_snapshots.sql
```

### 1.3 Export Encryption Key and Data

```bash
# Export encryption key from Docker volume
docker cp hyper-arena-app:/app/data/.encryption_key ./.encryption_key

# Create local data directory
mkdir -p ./data
cp ./.encryption_key ./data/.encryption_key
```

## Step 2: Set Up Local PostgreSQL

### 2.1 Create PostgreSQL User and Databases

```bash
# Start PostgreSQL if not running
brew services start postgresql@14

# Create user (if it doesn't exist)
createuser -s alpha_user

# Set password for the user
psql postgres -c "ALTER USER alpha_user WITH PASSWORD 'alpha_pass';"

# Create databases
createdb -U alpha_user alpha_arena
createdb -U alpha_user alpha_snapshots

# Grant privileges
psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE alpha_arena TO alpha_user;"
psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE alpha_snapshots TO alpha_user;"
```

### 2.2 Import Data into Local PostgreSQL

**If you used custom format (.dump):**

```bash
# Import main database
pg_restore -U alpha_user -d alpha_arena -v ./alpha_arena.dump

# Import snapshots database
pg_restore -U alpha_user -d alpha_snapshots -v ./alpha_snapshots.dump
```

**If you used SQL format (.sql):**

```bash
# Import main database
psql -U alpha_user -d alpha_arena < ./alpha_arena.sql

# Import snapshots database
psql -U alpha_user -d alpha_snapshots < ./alpha_snapshots.sql
```

### 2.3 Verify Import

```bash
# Check main database
psql -U alpha_user -d alpha_arena -c "\dt"

# Check snapshots database
psql -U alpha_user -d alpha_snapshots -c "\dt"
```

## Step 3: Configure Backend for Local Development

### 3.1 Create .env File for Backend

Create `backend/.env`:

```env
# Database connections (localhost instead of postgres service)
DATABASE_URL=postgresql://alpha_user:alpha_pass@localhost:5432/alpha_arena
SNAPSHOT_DATABASE_URL=postgresql://alpha_user:alpha_pass@localhost:5432/alpha_snapshots

# Encryption key path
HYPERLIQUID_ENCRYPTION_KEY_FILE=../data/.encryption_key

# Optional: Database pool settings
DB_POOL_SIZE=20
DB_POOL_MAX_OVERFLOW=20
DB_POOL_RECYCLE=1800
DB_POOL_TIMEOUT=30

# Disable proxy settings
HTTP_PROXY=
HTTPS_PROXY=
http_proxy=
https_proxy=
ALL_PROXY=
NO_PROXY=
no_proxy=
```

### 3.2 Update Backend main.py to Load Encryption Key

Edit `backend/main.py` to load the encryption key from file:

```python
import os
from pathlib import Path

# Load encryption key at startup
def load_encryption_key():
    key_file = os.environ.get("HYPERLIQUID_ENCRYPTION_KEY_FILE", "../data/.encryption_key")
    key_path = Path(__file__).parent.parent / key_file.lstrip("../")
    
    if key_path.exists():
        with open(key_path, "r") as f:
            key = f.read().strip()
            os.environ["HYPERLIQUID_ENCRYPTION_KEY"] = key
            return key
    else:
        # Generate new key if not exists
        from cryptography.fernet import Fernet
        key = Fernet.generate_key().decode()
        key_path.parent.mkdir(parents=True, exist_ok=True)
        with open(key_path, "w") as f:
            f.write(key)
        os.environ["HYPERLIQUID_ENCRYPTION_KEY"] = key
        return key

# Load at module level
load_encryption_key()
```

### 3.3 Install Backend Dependencies

```bash
cd backend

# Using pip
pip install -e .

# OR using uv (faster)
pip install uv
uv pip install -e .
```

### 3.4 Run Database Migrations

```bash
cd backend

# Initialize databases (if not imported from Docker)
python -m database.init_postgresql
python database/init_hyperliquid_tables.py
python database/init_snapshot_db.py
```

## Step 4: Configure Frontend for Local Development

### 4.1 Create .env File for Frontend

Create `frontend/.env.local`:

```env
# Backend API URL
VITE_API_URL=http://localhost:8802
```

### 4.2 Update API Configuration (if needed)

The frontend should already be configured to work with the backend. Verify `frontend/app/lib/api.ts` uses the correct base URL.

### 4.3 Install Frontend Dependencies

```bash
cd frontend

# Install dependencies
pnpm install
```

## Step 5: Run Development Servers

### 5.1 Start Backend (Terminal 1)

```bash
cd backend

# With hot reload using uvicorn
uvicorn main:app --reload --host 0.0.0.0 --port 8802

# OR with more verbose logging
uvicorn main:app --reload --host 0.0.0.0 --port 8802 --log-level debug
```

The backend will run on `http://localhost:8802` with hot-reload enabled.

### 5.2 Start Frontend (Terminal 2)

```bash
cd frontend

# Start Vite dev server with hot reload
pnpm dev
```

The frontend will run on `http://localhost:5173` (or next available port) with hot-reload enabled.

### 5.3 Access the Application

- **Frontend**: http://localhost:5173
- **Backend API**: http://localhost:8802
- **API Docs**: http://localhost:8802/docs

## Step 6: Stop Docker (Optional)

If you want to completely stop Docker to free up resources:

```bash
# Stop all containers
docker-compose down

# Stop and remove volumes (CAUTION: This deletes Docker data)
# docker-compose down -v
```

## Development Workflow

### Making Changes

1. **Backend Changes**: Edit any Python file in `backend/`, uvicorn will automatically reload
2. **Frontend Changes**: Edit any file in `frontend/app/`, Vite will hot-reload the browser
3. **Database Changes**: Run migrations manually or use your database tool

### Viewing Logs

- **Backend**: Logs appear in Terminal 1 where uvicorn is running
- **Frontend**: Logs appear in Terminal 2 and browser console
- **Database**: Use `psql` or a GUI tool like pgAdmin/TablePlus

### Debugging

- **Backend**: Add breakpoints if using an IDE, or use `print()` / `logging` statements
- **Frontend**: Use browser DevTools, React DevTools
- **Database**: Connect directly with `psql -U alpha_user -d alpha_arena`

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 8802
lsof -ti:8802 | xargs kill -9

# Find process using port 5173
lsof -ti:5173 | xargs kill -9
```

### Database Connection Issues

```bash
# Check PostgreSQL is running
brew services list

# Start PostgreSQL
brew services start postgresql@14

# Check connection
psql -U alpha_user -d alpha_arena -c "SELECT 1;"
```

### Missing Dependencies

```bash
# Backend
cd backend && pip install -e .

# Frontend
cd frontend && pnpm install
```

### Encryption Key Issues

```bash
# Verify encryption key exists
cat data/.encryption_key

# Regenerate if needed (CAUTION: Will invalidate encrypted data)
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" > data/.encryption_key
```

## Notes

- Database files are stored at `~/Library/Application Support/Postgres/` (macOS default)
- Your local PostgreSQL uses the same credentials as Docker for consistency
- The encryption key is critical for decrypting sensitive data like API keys
- Frontend and backend run on different ports during development
- All changes are reflected immediately without rebuilding Docker images

## Next Steps

When you're ready to go back to Docker, see [`docker_compile.md`](./docker_compile.md).
