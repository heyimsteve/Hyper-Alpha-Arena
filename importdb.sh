#!/bin/bash

# Import PostgreSQL database for Hyper-Alpha-Arena
# This script imports a database export file created by exportdb.sh

set -e  # Exit on error

# Database configuration
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="alpha_arena"
DB_USER="alpha_user"
DB_PASSWORD="alpha_pass"

# Check if import file is provided
if [ -z "$1" ]; then
    echo "Usage: ./importdb.sh <export_file.sql>"
    echo ""
    echo "Example:"
    echo "  ./importdb.sh ./db_exports/alpha_arena_20231201_123456.sql"
    echo "  ./importdb.sh ./db_exports/latest.sql"
    exit 1
fi

IMPORT_FILE="$1"

# Check if file exists
if [ ! -f "$IMPORT_FILE" ]; then
    echo "Error: File not found: $IMPORT_FILE"
    exit 1
fi

echo "=========================================="
echo "Hyper-Alpha-Arena Database Import"
echo "=========================================="
echo ""
echo "Import file: $IMPORT_FILE"
echo "Target database: $DB_NAME"
echo ""
echo "⚠️  WARNING: This will DROP and RECREATE the database!"
echo "   All existing data in '$DB_NAME' will be lost."
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Import cancelled."
    exit 0
fi

echo ""
echo "Step 1: Dropping existing database (if exists)..."
PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d postgres \
    -c "DROP DATABASE IF EXISTS $DB_NAME;" 2>/dev/null || true

echo "Step 2: Creating fresh database..."
PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d postgres \
    -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"

echo "Step 3: Importing data..."
PGPASSWORD="$DB_PASSWORD" psql \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -f "$IMPORT_FILE" \
    -q

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Import completed successfully!"
    echo ""
    echo "Database '$DB_NAME' has been restored."
    echo "You can now start the application with: pnpm local"
    echo ""
else
    echo ""
    echo "✗ Import failed!"
    exit 1
fi
