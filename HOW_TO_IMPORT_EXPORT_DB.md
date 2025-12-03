# Database Import/Export Guide

This guide explains how to migrate your Hyper Alpha Arena database from one device to another, allowing you to continue development seamlessly across different machines.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Exporting the Database](#exporting-the-database)
- [Transferring Files](#transferring-files)
- [Importing the Database](#importing-the-database)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)

---

## Overview

The Hyper Alpha Arena application uses PostgreSQL running in Docker to store:
- **alpha_arena**: Main database (users, accounts, trades, AI decisions, etc.)
- **alpha_snapshots**: Historical snapshots of portfolio performance
- **Encryption Key**: Critical for decrypting Hyperliquid private keys

The export/import scripts handle all of these components automatically.

---

## Prerequisites

Before starting, ensure you have:

### On Source Device (Exporting)
- ✅ Docker and docker-compose installed
- ✅ Hyper Alpha Arena running (`docker-compose up -d`)
- ✅ Python 3.8+ installed
- ✅ Access to the project directory

### On Target Device (Importing)
- ✅ Docker and docker-compose installed
- ✅ Fresh clone of Hyper Alpha Arena repository
- ✅ Python 3.8+ installed
- ✅ Docker containers started (`docker-compose up -d`)

---

## Exporting the Database

### Step 1: Navigate to Project Directory

```bash
cd /path/to/Hyper-Alpha-Arena
```

### Step 2: Ensure Application is Running

```bash
docker-compose up -d
```

Verify containers are running:
```bash
docker ps
```

You should see:
- `hyper-arena-postgres`
- `hyper-arena-app`

### Step 3: Run Export Script

```bash
python backend/database/export_db.py
```

Or specify a custom output directory:
```bash
python backend/database/export_db.py --output-dir ./my_exports
```

### Step 4: Verify Export

The script will create a `db_exports` directory (or your custom directory) containing:

```
db_exports/
├── main_db_20231203_143022.sql           # Main database dump
├── snapshots_db_20231203_143022.sql      # Snapshots database dump
├── encryption_key_20231203_143022.txt    # Encryption key (if exists)
└── export_manifest_20231203_143022.txt   # Export metadata
```

**Expected Output:**
```
============================================================
Hyper Alpha Arena Database Export
============================================================

📦 Exporting alpha_arena to main_db_20231203_143022.sql...
✅ Successfully exported alpha_arena (2.45 MB)
📦 Exporting alpha_snapshots to snapshots_db_20231203_143022.sql...
✅ Successfully exported alpha_snapshots (0.83 MB)
🔑 Exporting encryption key to encryption_key_20231203_143022.txt...
✅ Successfully exported encryption key
📋 Created export manifest: export_manifest_20231203_143022.txt

============================================================
✅ Export completed successfully!
   All 3 items exported to: /path/to/db_exports
============================================================
```

---

## Transferring Files

Transfer the entire export directory to your target device using one of these methods:

### Option 1: USB Drive / External Storage

```bash
# On source device
cp -r db_exports /Volumes/USBDrive/

# On target device
cp -r /Volumes/USBDrive/db_exports ~/Downloads/
```

### Option 2: Cloud Storage (Dropbox, Google Drive, etc.)

```bash
# Upload to cloud
cp -r db_exports ~/Dropbox/hyper-arena-backup/

# Download on target device
# (Use cloud storage client)
```

### Option 3: SCP (if devices are networked)

```bash
# From source device
scp -r db_exports user@target-device:/home/user/Downloads/
```

### Option 4: Compressed Archive

For faster transfer:

```bash
# On source device
tar -czf db_exports.tar.gz db_exports/

# Transfer the .tar.gz file, then on target device
tar -xzf db_exports.tar.gz
```

⚠️ **Security Note**: The export contains sensitive data including:
- User information and encrypted private keys
- Trading history and AI decisions
- Account credentials (encrypted)

**Always use secure transfer methods and delete exports after successful import!**

---

## Importing the Database

### Step 1: Set Up Target Device

```bash
# Clone the repository (if not already done)
git clone <repository-url> Hyper-Alpha-Arena
cd Hyper-Alpha-Arena

# Start Docker containers
docker-compose up -d

# Wait for containers to be healthy (about 30 seconds)
docker ps
```

### Step 2: Locate Exported Files

Place your exported files in an accessible location:

```bash
# Example: using Downloads directory
ls ~/Downloads/db_exports/
```

### Step 3: Run Import Script

```bash
python backend/database/import_db.py --import-dir ~/Downloads/db_exports
```

The script will prompt for confirmation:

```
⚠️  WARNING: This will replace all existing data in the databases!
Are you sure you want to continue? (yes/no): 
```

Type `yes` and press Enter.

To skip the confirmation prompt (for automation):
```bash
python backend/database/import_db.py --import-dir ~/Downloads/db_exports --yes
```

### Step 4: Verify Import

**Expected Output:**
```
============================================================
Hyper Alpha Arena Database Import
============================================================

📄 Found main_db: main_db_20231203_143022.sql
📄 Found snapshots_db: snapshots_db_20231203_143022.sql
🔑 Found encryption key: encryption_key_20231203_143022.txt

📥 Importing main_db_20231203_143022.sql into alpha_arena...
📊 Database alpha_arena already exists
✅ Successfully imported alpha_arena
📥 Importing snapshots_db_20231203_143022.sql into alpha_snapshots...
📊 Database alpha_snapshots already exists
✅ Successfully imported alpha_snapshots
🔑 Importing encryption key from encryption_key_20231203_143022.txt...
✅ Successfully imported encryption key

============================================================
✅ Import completed successfully!
============================================================
```

### Step 5: Restart Application

```bash
docker-compose restart app
```

### Step 6: Verify Data

Open the application in your browser:
```
http://localhost:8802
```

Check that:
- ✅ Your user accounts are present
- ✅ Trading history is visible
- ✅ Hyperliquid accounts work (if encryption key was imported)
- ✅ Portfolio snapshots are available

---

## Troubleshooting

### Export Issues

#### "Docker container not running"
```bash
# Start containers
docker-compose up -d

# Check status
docker ps
```

#### "Permission denied"
```bash
# Make script executable
chmod +x backend/database/export_db.py

# Or run with python explicitly
python backend/database/export_db.py
```

#### "Export file is empty or very small"
```bash
# Check if database has data
docker exec -i hyper-arena-postgres psql -U alpha_user -d alpha_arena -c "SELECT COUNT(*) FROM users;"

# If empty, you may not have any data to export
```

### Import Issues

#### "Import directory does not exist"
```bash
# Verify the path is correct
ls -la ~/Downloads/db_exports/

# Use absolute path
python backend/database/import_db.py --import-dir /full/path/to/db_exports
```

#### "Error importing database: relation already exists"
This is normal if the database has existing tables. The import script uses `--clean` flag to drop existing tables before importing.

#### "Encryption key import failed"
If you don't have an encryption key:
1. You can still use the application
2. You'll need to reconfigure Hyperliquid accounts
3. Previous encrypted private keys won't be accessible

#### "Database connection refused"
```bash
# Ensure PostgreSQL container is healthy
docker ps

# Check logs
docker logs hyper-arena-postgres

# Restart if needed
docker-compose restart postgres
```

### Verification Issues

#### "Can't access application after import"
```bash
# Check application logs
docker logs hyper-arena-app

# Restart application
docker-compose restart app

# Full restart if needed
docker-compose down
docker-compose up -d
```

#### "Hyperliquid accounts not working"
If encryption key wasn't imported or is different:
1. Go to Account Management in the UI
2. Reconfigure your Hyperliquid accounts
3. Re-enter private keys (they will be encrypted with new key)

---

## Advanced Usage

### Automated Backups

Create a cron job for regular exports:

```bash
# Edit crontab
crontab -e

# Add daily backup at 2 AM
0 2 * * * cd /path/to/Hyper-Alpha-Arena && python backend/database/export_db.py --output-dir /backups/hyper-arena/$(date +\%Y\%m\%d)
```

### Selective Database Import

If you only want to import specific databases, manually specify the SQL file:

```bash
# Import only main database
docker exec -i hyper-arena-postgres psql -U alpha_user -d alpha_arena < db_exports/main_db_20231203_143022.sql
```

### Remote Database Export

Export directly from a remote server:

```bash
# SSH into remote server
ssh user@remote-server

# Export database
cd /path/to/Hyper-Alpha-Arena
python backend/database/export_db.py

# Download to local machine
scp -r user@remote-server:/path/to/Hyper-Alpha-Arena/db_exports ./
```

### Inspecting Export Files

View what's in an export without importing:

```bash
# View SQL file structure
head -n 50 db_exports/main_db_20231203_143022.sql

# Count number of INSERT statements (approximate row count)
grep -c "INSERT INTO" db_exports/main_db_20231203_143022.sql

# View tables being exported
grep "CREATE TABLE" db_exports/main_db_20231203_143022.sql
```

### Merging Data from Multiple Exports

If you need to merge data from different sources, you'll need to:
1. Import the first export normally
2. Manually edit the second export SQL file to remove DROP/CREATE statements
3. Import only the INSERT statements from the second export

This is advanced and requires careful handling to avoid conflicts.

---

## Best Practices

### Security

- 🔒 **Encrypt exports** when transferring over networks
- 🔒 **Delete old exports** after successful import
- 🔒 **Use secure transfer methods** (SCP, encrypted cloud storage)
- 🔒 **Don't commit exports to git** (they're in .gitignore)

### Backup Strategy

- 📅 **Regular exports**: Daily or before major changes
- 📅 **Version your exports**: Keep dated backups
- 📅 **Test imports**: Periodically verify imports work
- 📅 **Store redundantly**: Keep copies in multiple locations

### Before Major Changes

Always export before:
- 🔄 Updating the application
- 🔄 Running database migrations
- 🔄 Making significant configuration changes
- 🔄 Testing new features

---

## Quick Reference

### Export Command
```bash
python backend/database/export_db.py --output-dir ./db_exports
```

### Import Command
```bash
python backend/database/import_db.py --import-dir ./db_exports
```

### Restart After Import
```bash
docker-compose restart app
```

---

## Support

If you encounter issues not covered in this guide:

1. Check Docker logs: `docker logs hyper-arena-app`
2. Check PostgreSQL logs: `docker logs hyper-arena-postgres`
3. Verify container status: `docker ps`
4. Review export manifest file for details about what was exported

---

**Last Updated**: December 2024  
**Tested With**: PostgreSQL 14, Docker 24.x, Python 3.9+
