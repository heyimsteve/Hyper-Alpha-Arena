#!/usr/bin/env python3
"""
PostgreSQL Database Import Script for Hyper Alpha Arena

This script imports database dump files exported from another device and restores
both the main database (alpha_arena) and snapshots database (alpha_snapshots).

Usage:
    python import_db.py --import-dir PATH

The script will import all SQL dump files found in the specified directory.
"""

import subprocess
import sys
import os
from pathlib import Path
import argparse
import re


class DatabaseImporter:
    def __init__(self, import_dir: str):
        self.import_dir = Path(import_dir)
        
        if not self.import_dir.exists():
            raise ValueError(f"Import directory does not exist: {import_dir}")
        
        # Database connection details (from docker-compose.yml)
        self.db_host = os.environ.get("DB_HOST", "localhost")
        self.db_port = os.environ.get("DB_PORT", "5432")
        self.db_user = os.environ.get("DB_USER", "alpha_user")
        self.db_password = os.environ.get("DB_PASSWORD", "alpha_pass")
        
        # Database mapping
        self.databases = {
            "main_db": "alpha_arena",
            "snapshots_db": "alpha_snapshots"
        }
    
    def check_docker_running(self) -> bool:
        """Check if Docker container is running."""
        try:
            result = subprocess.run(
                ["docker", "ps", "--filter", "name=hyper-arena-postgres", "--format", "{{.Names}}"],
                capture_output=True,
                text=True,
                check=True
            )
            return "hyper-arena-postgres" in result.stdout
        except subprocess.CalledProcessError:
            return False
    
    def find_export_files(self) -> dict:
        """
        Find all export files in the import directory.
        
        Returns:
            Dictionary mapping database prefix to SQL file path
        """
        files = {}
        
        for prefix in self.databases.keys():
            # Find the most recent file matching the prefix
            pattern = f"{prefix}_*.sql"
            matching_files = sorted(self.import_dir.glob(pattern), reverse=True)
            
            if matching_files:
                files[prefix] = matching_files[0]
                print(f"📄 Found {prefix}: {matching_files[0].name}")
            else:
                print(f"⚠️  No file found for {prefix} (pattern: {pattern})")
        
        # Find encryption key
        key_files = sorted(self.import_dir.glob("encryption_key_*.txt"), reverse=True)
        if key_files:
            files["encryption_key"] = key_files[0]
            print(f"🔑 Found encryption key: {key_files[0].name}")
        else:
            print(f"⚠️  No encryption key found")
        
        return files
    
    def verify_database_exists(self, db_name: str) -> bool:
        """Check if a database exists in PostgreSQL."""
        try:
            cmd = [
                "docker", "exec", "-i", "hyper-arena-postgres",
                "psql",
                "-U", self.db_user,
                "-lqt"
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                env={**os.environ, "PGPASSWORD": self.db_password}
            )
            
            return db_name in result.stdout
            
        except Exception as e:
            print(f"❌ Error checking database: {str(e)}")
            return False
    
    def drop_database(self, db_name: str) -> bool:
        """Drop a database if it exists."""
        try:
            print(f"🗑️  Dropping existing database {db_name}...")
            
            # Terminate all connections to the database first
            terminate_cmd = [
                "docker", "exec", "-i", "hyper-arena-postgres",
                "psql",
                "-U", self.db_user,
                "-d", "postgres",
                "-c", f"SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '{db_name}';"
            ]
            
            subprocess.run(
                terminate_cmd,
                capture_output=True,
                text=True,
                env={**os.environ, "PGPASSWORD": self.db_password}
            )
            
            # Drop the database
            drop_cmd = [
                "docker", "exec", "-i", "hyper-arena-postgres",
                "psql",
                "-U", self.db_user,
                "-d", "postgres",
                "-c", f"DROP DATABASE IF EXISTS {db_name};"
            ]
            
            result = subprocess.run(
                drop_cmd,
                capture_output=True,
                text=True,
                env={**os.environ, "PGPASSWORD": self.db_password}
            )
            
            if result.returncode != 0:
                print(f"❌ Error dropping database: {result.stderr}")
                return False
            
            print(f"✅ Database {db_name} dropped successfully")
            return True
            
        except Exception as e:
            print(f"❌ Error dropping database: {str(e)}")
            return False
    
    def create_database_if_needed(self, db_name: str, force_recreate: bool = True) -> bool:
        """Create database, optionally dropping it first if it exists."""
        if self.verify_database_exists(db_name):
            if force_recreate:
                print(f"📊 Database {db_name} already exists, will recreate it")
                if not self.drop_database(db_name):
                    return False
            else:
                print(f"📊 Database {db_name} already exists")
                return True
        
        print(f"📊 Creating database {db_name}...")
        
        try:
            cmd = [
                "docker", "exec", "-i", "hyper-arena-postgres",
                "psql",
                "-U", self.db_user,
                "-d", "postgres",
                "-c", f"CREATE DATABASE {db_name};"
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                env={**os.environ, "PGPASSWORD": self.db_password}
            )
            
            if result.returncode != 0 and "already exists" not in result.stderr:
                print(f"❌ Error creating database: {result.stderr}")
                return False
            
            print(f"✅ Database {db_name} created successfully")
            return True
            
        except Exception as e:
            print(f"❌ Error creating database: {str(e)}")
            return False
    
    def import_database(self, sql_file: Path, db_name: str) -> bool:
        """
        Import a SQL dump file into a database.
        
        Args:
            sql_file: Path to the SQL dump file
            db_name: Name of the target database
            
        Returns:
            True if successful, False otherwise
        """
        print(f"📥 Importing {sql_file.name} into {db_name}...")
        
        try:
            # Ensure database exists
            if not self.create_database_if_needed(db_name):
                return False
            
            # Import the SQL dump
            cmd = [
                "docker", "exec", "-i", "hyper-arena-postgres",
                "psql",
                "-U", self.db_user,
                "-d", db_name
            ]
            
            with open(sql_file, 'r') as f:
                result = subprocess.run(
                    cmd,
                    stdin=f,
                    capture_output=True,
                    text=True,
                    env={**os.environ, "PGPASSWORD": self.db_password}
                )
            
            # Check for errors (ignore NOTICEs)
            if result.returncode != 0:
                # Filter out common non-critical messages
                error_lines = [
                    line for line in result.stderr.split('\n')
                    if line and 
                    not line.startswith('NOTICE:') and
                    not line.startswith('WARNING:') and
                    'does not exist, skipping' not in line
                ]
                
                if error_lines:
                    print(f"❌ Error importing {db_name}:")
                    print('\n'.join(error_lines))
                    return False
            
            print(f"✅ Successfully imported {db_name}")
            return True
            
        except Exception as e:
            print(f"❌ Error importing {db_name}: {str(e)}")
            return False
    
    def import_encryption_key(self, key_file: Path) -> bool:
        """
        Import the encryption key into Docker volume.
        This is critical for decrypting Hyperliquid private keys.
        """
        print(f"🔑 Importing encryption key from {key_file.name}...")
        
        try:
            # Read the encryption key
            with open(key_file, 'r') as f:
                key_content = f.read().strip()
            
            if not key_content:
                print(f"❌ Encryption key file is empty")
                return False
            
            # Create the data directory if it doesn't exist
            subprocess.run(
                ["docker", "exec", "-i", "hyper-arena-app", "mkdir", "-p", "/app/data"],
                capture_output=True
            )
            
            # Write the encryption key to the container
            cmd = [
                "docker", "exec", "-i", "hyper-arena-app",
                "sh", "-c", "cat > /app/data/.encryption_key"
            ]
            
            result = subprocess.run(
                cmd,
                input=key_content,
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                print(f"❌ Error importing encryption key: {result.stderr}")
                return False
            
            print(f"✅ Successfully imported encryption key")
            return True
            
        except Exception as e:
            print(f"❌ Error importing encryption key: {str(e)}")
            return False
    
    def run(self, skip_confirmation: bool = False) -> bool:
        """Execute the complete import process."""
        print("=" * 60)
        print("Hyper Alpha Arena Database Import")
        print("=" * 60)
        print()
        
        # Check if Docker is running
        if not self.check_docker_running():
            print("❌ Error: Docker container 'hyper-arena-postgres' is not running.")
            print("   Please start the application with: docker-compose up -d")
            return False
        
        print(f"Import directory: {self.import_dir.absolute()}\n")
        
        # Find export files
        export_files = self.find_export_files()
        
        if not export_files:
            print("❌ No export files found in the import directory.")
            return False
        
        print()
        
        # Confirmation
        if not skip_confirmation:
            print("⚠️  WARNING: This will replace all existing data in the databases!")
            response = input("Are you sure you want to continue? (yes/no): ")
            if response.lower() not in ['yes', 'y']:
                print("Import cancelled.")
                return False
            print()
        
        # Import databases
        success = True
        
        for prefix, db_name in self.databases.items():
            if prefix in export_files:
                if not self.import_database(export_files[prefix], db_name):
                    success = False
            else:
                print(f"⚠️  Skipping {db_name} (no export file found)")
        
        # Import encryption key
        if "encryption_key" in export_files:
            if not self.import_encryption_key(export_files["encryption_key"]):
                print("⚠️  Warning: Encryption key import failed. You may need to reconfigure accounts.")
        
        # Summary
        print()
        print("=" * 60)
        
        if success:
            print(f"✅ Import completed successfully!")
            print()
            print("Next steps:")
            print("  1. Restart the application: docker-compose restart app")
            print("  2. Verify your data is correctly imported")
            print("  3. If you imported an encryption key, your accounts should work")
            print("  4. If no encryption key was imported, you'll need to reconfigure accounts")
            return True
        else:
            print(f"⚠️  Import completed with errors")
            print(f"   Check the output above for details")
            return False


def main():
    parser = argparse.ArgumentParser(
        description="Import Hyper Alpha Arena PostgreSQL databases"
    )
    parser.add_argument(
        "--import-dir",
        required=True,
        help="Directory containing exported SQL files"
    )
    parser.add_argument(
        "--yes",
        action="store_true",
        help="Skip confirmation prompt"
    )
    
    args = parser.parse_args()
    
    try:
        importer = DatabaseImporter(import_dir=args.import_dir)
        success = importer.run(skip_confirmation=args.yes)
        
        sys.exit(0 if success else 1)
        
    except ValueError as e:
        print(f"❌ Error: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
