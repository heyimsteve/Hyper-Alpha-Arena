#!/bin/bash
# Docker Compilation Helper Script
# This script automates the process of compiling development changes back into Docker

set -e  # Exit on error

echo "🐳 Hyper Alpha Arena - Docker Compilation Helper"
echo "================================================="
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

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

print_success "Docker is installed"

# Step 1: Export local databases
echo ""
echo "Step 1: Exporting local databases..."
echo "-------------------------------------"

# Check if local PostgreSQL is running
if ! pg_isready -q; then
    print_error "Local PostgreSQL is not running. Start it with:"
    echo "  brew services start postgresql@14"
    exit 1
fi

print_info "Exporting alpha_arena database..."
pg_dump -U alpha_user -d alpha_arena > ./alpha_arena_local.sql
print_success "Exported alpha_arena_local.sql"

print_info "Exporting alpha_snapshots database..."
pg_dump -U alpha_user -d alpha_snapshots > ./alpha_snapshots_local.sql
print_success "Exported alpha_snapshots_local.sql"

# Step 2: Clean up development files
echo ""
echo "Step 2: Backing up development environment files..."
echo "----------------------------------------------------"

if [ -f backend/.env ]; then
    cp backend/.env backend/.env.backup
    print_success "Backed up backend/.env"
fi

if [ -f frontend/.env.local ]; then
    cp frontend/.env.local frontend/.env.local.backup
    print_success "Backed up frontend/.env.local"
fi

# Step 3: Build Docker images
echo ""
echo "Step 3: Building Docker images..."
echo "----------------------------------"

read -p "Build with cache (faster) or without cache (clean build)? (with/without) " -n 1 -r
echo
if [[ $REPLY =~ ^[Ww]ithout$ ]] || [[ $REPLY =~ ^[Nn]$ ]]; then
    print_info "Building without cache..."
    docker-compose build --no-cache
else
    print_info "Building with cache..."
    docker-compose build
fi

print_success "Docker images built"

# Step 4: Start PostgreSQL container
echo ""
echo "Step 4: Starting PostgreSQL container..."
echo "-----------------------------------------"

docker-compose up -d postgres
print_info "Waiting for PostgreSQL to be healthy..."
sleep 10

# Wait for health check
for i in {1..30}; do
    if docker-compose ps postgres | grep -q "healthy"; then
        print_success "PostgreSQL is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        print_error "PostgreSQL health check timeout"
        exit 1
    fi
    sleep 2
done

# Step 5: Import data into Docker PostgreSQL
echo ""
echo "Step 5: Importing data into Docker PostgreSQL..."
echo "-------------------------------------------------"

read -p "Import local data into Docker? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Copying SQL files to container..."
    docker cp ./alpha_arena_local.sql hyper-arena-postgres:/tmp/alpha_arena.sql
    docker cp ./alpha_snapshots_local.sql hyper-arena-postgres:/tmp/alpha_snapshots.sql
    
    print_info "Importing alpha_arena..."
    docker exec hyper-arena-postgres psql -U alpha_user -d alpha_arena -f /tmp/alpha_arena.sql > /dev/null 2>&1
    print_success "Imported alpha_arena"
    
    print_info "Importing alpha_snapshots..."
    docker exec hyper-arena-postgres psql -U alpha_user -d alpha_snapshots -f /tmp/alpha_snapshots.sql > /dev/null 2>&1
    print_success "Imported alpha_snapshots"
else
    print_warning "Skipped data import. Docker will use existing data or initialize fresh."
fi

# Step 6: Restore encryption key
echo ""
echo "Step 6: Restoring encryption key to Docker..."
echo "----------------------------------------------"

# Start app container temporarily
docker-compose up -d app
sleep 10

if [ -f ./data/.encryption_key ]; then
    docker cp ./data/.encryption_key hyper-arena-app:/app/data/.encryption_key
    print_success "Copied encryption key to Docker"
    
    # Verify
    if docker exec hyper-arena-app test -f /app/data/.encryption_key; then
        print_success "Encryption key verified in container"
    else
        print_error "Failed to copy encryption key"
    fi
else
    print_warning "No encryption key found at ./data/.encryption_key"
    print_warning "Docker will generate a new one on startup"
fi

# Step 7: Restart application
echo ""
echo "Step 7: Restarting application..."
echo "----------------------------------"

docker-compose down
docker-compose up -d

print_info "Waiting for services to start..."
sleep 15

# Step 8: Verify health
echo ""
echo "Step 8: Verifying application health..."
echo "----------------------------------------"

# Check container status
if docker-compose ps | grep -q "hyper-arena-app" && docker-compose ps | grep -q "hyper-arena-postgres"; then
    print_success "All containers are running"
else
    print_error "Some containers failed to start"
    docker-compose ps
    exit 1
fi

# Check health endpoint
print_info "Checking health endpoint..."
for i in {1..30}; do
    if curl -s http://localhost:8802/api/health | grep -q "healthy"; then
        print_success "Application is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        print_warning "Health check timeout. Check logs with: docker-compose logs app"
    fi
    sleep 2
done

# Step 9: Clean up (optional)
echo ""
echo "Step 9: Clean up..."
echo "-------------------"

read -p "Stop local PostgreSQL? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    brew services stop postgresql@14
    print_success "Stopped local PostgreSQL"
else
    print_warning "Local PostgreSQL still running"
fi

read -p "Remove local database export files? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -f alpha_arena_local.sql alpha_snapshots_local.sql
    print_success "Removed local export files"
else
    print_warning "Local export files kept"
fi

# Final summary
echo ""
echo "================================================"
echo -e "${GREEN}✓ Docker Compilation Complete!${NC}"
echo "================================================"
echo ""
echo "Application Status:"
docker-compose ps
echo ""
echo "Access URLs:"
echo "  Application: http://localhost:8802"
echo "  API Docs:    http://localhost:8802/docs"
echo "  Health:      http://localhost:8802/api/health"
echo ""
echo "Useful commands:"
echo "  View logs:       docker-compose logs -f app"
echo "  Restart:         docker-compose restart app"
echo "  Stop:            docker-compose down"
echo ""
echo "For more details, see docker_compile.md"
echo ""
