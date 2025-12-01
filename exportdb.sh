#!/bin/bash

# Export PostgreSQL database for Hyper-Alpha-Arena
# This script exports the database to a file that can be imported on another device

set -e  # Exit on error

# Database configuration
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="alpha_arena"
DB_USER="alpha_user"
DB_PASSWORD="alpha_pass"

# Export configuration
EXPORT_DIR="./db_exports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
EXPORT_FILE="$EXPORT_DIR/alpha_arena_${TIMESTAMP}.sql"

# Create export directory if it doesn't exist
mkdir -p "$EXPORT_DIR"

echo "=========================================="
echo "Hyper-Alpha-Arena Database Export"
echo "=========================================="
echo ""
echo "Exporting database: $DB_NAME"
echo "Export file: $EXPORT_FILE"
echo ""

# Export database using pg_dump
echo "Starting export..."
PGPASSWORD="$DB_PASSWORD" pg_dump \
    -h "$DB_HOST" \
    -p "$DB_PORT" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -F p \
    --no-owner \
    --no-acl \
    -f "$EXPORT_FILE"

if [ $? -eq 0 ]; then
    FILE_SIZE=$(du -h "$EXPORT_FILE" | cut -f1)
    echo ""
    echo "✓ Export completed successfully!"
    echo "  File: $EXPORT_FILE"
    echo "  Size: $FILE_SIZE"
    echo ""
    echo "To import on another device:"
    echo "  1. Copy $EXPORT_FILE to the other device"
    echo "  2. Run: ./importdb.sh $EXPORT_FILE"
    echo ""
    
    # Create a symlink to latest export
    ln -sf "$(basename "$EXPORT_FILE")" "$EXPORT_DIR/latest.sql"
    echo "  Shortcut: ./importdb.sh ./db_exports/latest.sql"
    echo ""
else
    echo ""
    echo "✗ Export failed!"
    exit 1
fi
