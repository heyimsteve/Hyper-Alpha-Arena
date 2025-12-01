#!/bin/bash
# Docker Separation Helper Script
# This script automates the process of exporting data from Docker and setting up local development

set -e  # Exit on error

echo "🚀 Hyper Alpha Arena - Docker Separation Helper"
echo "================================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

print_info() {
    echo -e "ℹ $1"
}

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker first."
    exit 1
fi

print_success "Docker is running"

# Step 1: Export Docker databases
echo ""
echo "Step 1: Exporting databases from Docker..."
echo "-------------------------------------------"

# Check if containers exist
if ! docker ps -a | grep -q hyper-arena-postgres; then
    print_warning "PostgreSQL container not found. Starting docker-compose..."
    docker-compose up -d postgres
    sleep 5
fi

# Export databases
print_info "Exporting alpha_arena database..."
docker exec hyper-arena-postgres pg_dump -U alpha_user -d alpha_arena > ./alpha_arena.sql
print_success "Exported alpha_arena.sql"

print_info "Exporting alpha_snapshots database..."
docker exec hyper-arena-postgres pg_dump -U alpha_user -d alpha_snapshots > ./alpha_snapshots.sql
print_success "Exported alpha_snapshots.sql"

# Step 2: Export encryption key
echo ""
echo "Step 2: Exporting encryption key..."
echo "------------------------------------"

# Start app container if needed
if ! docker ps | grep -q hyper-arena-app; then
    print_warning "App container not running. Starting..."
    docker-compose up -d app
    sleep 10
fi

# Create data directory
mkdir -p ./data

# Export encryption key
if docker exec hyper-arena-app test -f /app/data/.encryption_key; then
    docker cp hyper-arena-app:/app/data/.encryption_key ./data/.encryption_key
    print_success "Exported encryption key to ./data/.encryption_key"
else
    print_warning "Encryption key not found in container. Will generate new one."
    python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())" > ./data/.encryption_key
    print_success "Generated new encryption key"
fi

# Step 3: Check local PostgreSQL
echo ""
echo "Step 3: Checking local PostgreSQL..."
echo "-------------------------------------"

if ! command -v psql &> /dev/null; then
    print_error "PostgreSQL not found. Please install PostgreSQL 14+:"
    echo "  brew install postgresql@14"
    echo "  brew services start postgresql@14"
    exit 1
fi

print_success "PostgreSQL is installed"

# Check if PostgreSQL is running
if ! pg_isready -q; then
    print_warning "PostgreSQL is not running. Starting..."
    brew services start postgresql@14
    sleep 3
fi

print_success "PostgreSQL is running"

# Step 4: Create databases
echo ""
echo "Step 4: Setting up local databases..."
echo "--------------------------------------"

# Create user if doesn't exist
print_info "Creating database user..."
psql postgres -c "CREATE USER alpha_user WITH PASSWORD 'alpha_pass';" 2>/dev/null || print_warning "User already exists"
psql postgres -c "ALTER USER alpha_user WITH SUPERUSER;" 2>/dev/null

# Create databases
print_info "Creating databases..."
createdb -U alpha_user alpha_arena 2>/dev/null || print_warning "alpha_arena database already exists"
createdb -U alpha_user alpha_snapshots 2>/dev/null || print_warning "alpha_snapshots database already exists"

# Grant privileges
psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE alpha_arena TO alpha_user;" 2>/dev/null
psql postgres -c "GRANT ALL PRIVILEGES ON DATABASE alpha_snapshots TO alpha_user;" 2>/dev/null

print_success "Databases created"

# Step 5: Import data
echo ""
echo "Step 5: Importing data into local databases..."
echo "-----------------------------------------------"

print_info "Importing alpha_arena..."
psql -U alpha_user -d alpha_arena < ./alpha_arena.sql > /dev/null 2>&1
print_success "Imported alpha_arena"

print_info "Importing alpha_snapshots..."
psql -U alpha_user -d alpha_snapshots < ./alpha_snapshots.sql > /dev/null 2>&1
print_success "Imported alpha_snapshots"

# Step 6: Create backend .env
echo ""
echo "Step 6: Creating backend .env file..."
echo "--------------------------------------"

cat > backend/.env << 'EOF'
# Database connections (localhost for local development)
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
EOF

print_success "Created backend/.env"

# Step 7: Create frontend .env
echo ""
echo "Step 7: Creating frontend .env.local file..."
echo "---------------------------------------------"

cat > frontend/.env.local << 'EOF'
# Backend API URL for local development
VITE_API_URL=http://localhost:8802
EOF

print_success "Created frontend/.env.local"

# Step 8: Check Python version
echo ""
echo "Step 8: Checking Python version..."
echo "------------------------------------"

PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
PYTHON_MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
PYTHON_MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 12 ]); then
    print_warning "Python 3.12+ required, found $PYTHON_VERSION"
    print_info "Installing Python 3.12..."
    brew install python@3.12
    
    print_info "Setting up Python 3.12 as default..."
    # Remove old aliases if they exist
    sed -i '' '/alias python=/d' ~/.zshrc 2>/dev/null || true
    sed -i '' '/alias python3=/d' ~/.zshrc 2>/dev/null || true
    sed -i '' '/alias pip=/d' ~/.zshrc 2>/dev/null || true
    
    # Add new aliases
    echo "alias python=/opt/homebrew/bin/python3.12" >> ~/.zshrc
    echo "alias python3=/opt/homebrew/bin/python3.12" >> ~/.zshrc
    echo "alias pip='/opt/homebrew/bin/python3.12 -m pip'" >> ~/.zshrc
    
    # Apply to current session
    alias python=/opt/homebrew/bin/python3.12
    alias python3=/opt/homebrew/bin/python3.12
    alias pip='/opt/homebrew/bin/python3.12 -m pip'
    
    print_success "Python 3.12 installed and configured"
    print_warning "Note: Open a new terminal or run 'source ~/.zshrc' for changes to persist"
else
    print_success "Python $PYTHON_VERSION detected"
fi

# Step 9: Install dependencies
echo ""
echo "Step 9: Installing dependencies..."
echo "-----------------------------------"

# Backend
print_info "Installing backend dependencies..."
cd backend
pip install --break-system-packages -e . || {
    print_error "Failed to install backend dependencies"
    cd ..
    exit 1
}
cd ..
print_success "Backend dependencies installed"

# Check if pnpm is installed
if ! command -v pnpm &> /dev/null; then
    print_info "Installing pnpm..."
    npm install -g pnpm
    print_success "pnpm installed"
fi

# Frontend
print_info "Installing frontend dependencies..."
cd frontend
pnpm install || {
    print_error "Failed to install frontend dependencies"
    cd ..
    exit 1
}
cd ..
print_success "Frontend dependencies installed"

# Step 10: Stop Docker
echo ""
echo "Step 10: Stopping Docker containers..."
echo "--------------------------------------"

read -p "Do you want to stop Docker containers now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker-compose down
    print_success "Docker containers stopped"
else
    print_warning "Docker containers still running. Stop manually with: docker-compose down"
fi

# Final instructions
echo ""
echo "================================================"
echo -e "${GREEN}✓ Setup Complete!${NC}"
echo "================================================"
echo ""
echo "Next steps:"
echo ""
echo "1. Start the backend (Terminal 1):"
echo "   cd backend"
echo "   uvicorn main:app --reload --host 0.0.0.0 --port 8802"
echo ""
echo "2. Start the frontend (Terminal 2):"
echo "   cd frontend"
echo "   pnpm dev"
echo ""
echo "3. Access the application:"
echo "   Frontend: http://localhost:5173"
echo "   Backend:  http://localhost:8802"
echo "   API Docs: http://localhost:8802/docs"
echo ""
echo "For more details, see docker_separate.md"
echo ""
