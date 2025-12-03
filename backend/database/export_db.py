#!/usr/bin/env python3
"""
PostgreSQL Database Export Script for Hyper Alpha Arena

This script exports both the main database (alpha_arena) and snapshots database
(alpha_snapshots) to SQL dump files that can be imported on another device.

Usage:
    python export_db.py [--output-dir PATH]

The script will create timestamped SQL dump files in the specified output directory.
"""

import subprocess
import sys
import os
from datetime import datetime
from pathlib import Path
import argparse


class DatabaseExporter:
    def __init__(self, output_dir: str = "./db_exports"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        # Database connection details (from docker-compose.yml)
        self.db_host = os.environ.get("DB_HOST", "localhost")
        self.db_port = os.environ.get("DB_PORT", "5432")
        self.db_user = os.environ.get("DB_USER", "alpha_user")
        self.db_password = os.environ.get("DB_PASSWORD", "alpha_pass")
        
        # Databases to export
        self.databases = {
            "alpha_arena": "main_db",
            "alpha_snapshots": "snapshots_db"
        }
        
        # Timestamp for file naming
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
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
    
    def export_database(self, db_name: str, prefix: str) -> Path:
        """
        Export a single database to a SQL dump file.
        
        Args:
            db_name: Name of the database to export
            prefix: Prefix for the output file
            
        Returns:
            Path to the exported SQL file
        """
        output_file = self.output_dir / f"{prefix}_{self.timestamp}.sql"
        
        print(f"📦 Exporting {db_name} to {output_file.name}...")
        
        try:
            # Use docker exec to run pg_dump inside the container
            cmd = [
                "docker", "exec", "-i", "hyper-arena-postgres",
                "pg_dump",
                "-U", self.db_user,
                "-d", db_name,
                "--clean",  # Include DROP statements
                "--if-exists",  # Add IF EXISTS to DROP statements
                "--no-owner",  # Don't output commands to set ownership
                "--no-acl",  # Don't output commands to set access privileges
            ]
            
            with open(output_file, 'w') as f:
                result = subprocess.run(
                    cmd,
                    stdout=f,
                    stderr=subprocess.PIPE,
                    text=True,
                    env={**os.environ, "PGPASSWORD": self.db_password}
                )
            
            if result.returncode != 0:
                print(f"❌ Error exporting {db_name}:")
                print(result.stderr)
                return None
            
            # Get file size for confirmation
            file_size = output_file.stat().st_size
            size_mb = file_size / (1024 * 1024)
            print(f"✅ Successfully exported {db_name} ({size_mb:.2f} MB)")
            
            return output_file
            
        except Exception as e:
            print(f"❌ Error exporting {db_name}: {str(e)}")
            return None
    
    def export_encryption_key(self) -> Path:
        """
        Export the encryption key from Docker volume.
        This is critical for decrypting Hyperliquid private keys.
        """
        output_file = self.output_dir / f"encryption_key_{self.timestamp}.txt"
        
        print(f"🔑 Exporting encryption key to {output_file.name}...")
        
        try:
            # Copy encryption key from Docker volume
            cmd = [
                "docker", "exec", "-i", "hyper-arena-app",
                "cat", "/app/data/.encryption_key"
            ]
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True
            )
            
            if result.returncode != 0:
                print(f"⚠️  Warning: Could not export encryption key. It may not exist yet.")
                return None
            
            with open(output_file, 'w') as f:
                f.write(result.stdout)
            
            print(f"✅ Successfully exported encryption key")
            return output_file
            
        except Exception as e:
            print(f"⚠️  Warning: Could not export encryption key: {str(e)}")
            return None
    
    def create_export_manifest(self, exported_files: dict) -> Path:
        """Create a manifest file documenting the export."""
        manifest_file = self.output_dir / f"export_manifest_{self.timestamp}.txt"
        
        with open(manifest_file, 'w') as f:
            f.write("=" * 60 + "\n")
            f.write("Hyper Alpha Arena Database Export Manifest\n")
            f.write("=" * 60 + "\n\n")
            f.write(f"Export Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
            f.write(f"Source Host: {self.db_host}:{self.db_port}\n\n")
            f.write("Exported Files:\n")
            f.write("-" * 60 + "\n")
            
            for db_name, file_path in exported_files.items():
                if file_path:
                    f.write(f"  {db_name}: {file_path.name}\n")
                else:
                    f.write(f"  {db_name}: FAILED\n")
            
            f.write("\n" + "=" * 60 + "\n")
            f.write("Import Instructions:\n")
            f.write("-" * 60 + "\n")
            f.write("1. Copy all exported files to the new device\n")
            f.write("2. Ensure Docker and docker-compose are installed\n")
            f.write("3. Run: python backend/database/import_db.py --import-dir <path>\n")
            f.write("4. See HOW_TO_IMPORT_EXPORT_DB.md for detailed instructions\n")
        
        print(f"📋 Created export manifest: {manifest_file.name}")
        return manifest_file
    
    def run(self) -> bool:
        """Execute the complete export process."""
        print("=" * 60)
        print("Hyper Alpha Arena Database Export")
        print("=" * 60)
        print()
        
        # Check if Docker is running
        if not self.check_docker_running():
            print("❌ Error: Docker container 'hyper-arena-postgres' is not running.")
            print("   Please start the application with: docker-compose up -d")
            return False
        
        print(f"Output directory: {self.output_dir.absolute()}\n")
        
        exported_files = {}
        
        # Export each database
        for db_name, prefix in self.databases.items():
            result = self.export_database(db_name, prefix)
            exported_files[db_name] = result
        
        # Export encryption key
        key_file = self.export_encryption_key()
        if key_file:
            exported_files["encryption_key"] = key_file
        
        # Create manifest
        self.create_export_manifest(exported_files)
        
        # Summary
        print()
        print("=" * 60)
        success_count = sum(1 for v in exported_files.values() if v is not None)
        total_count = len(exported_files)
        
        if success_count == total_count:
            print(f"✅ Export completed successfully!")
            print(f"   All {total_count} items exported to: {self.output_dir.absolute()}")
            print()
            print("Next steps:")
            print("  1. Copy the entire export directory to your new device")
            print("  2. Run the import script on the new device")
            print("  3. See HOW_TO_IMPORT_EXPORT_DB.md for detailed instructions")
            return True
        else:
            print(f"⚠️  Export completed with warnings:")
            print(f"   {success_count}/{total_count} items exported successfully")
            print(f"   Check the output above for details")
            return False


def main():
    parser = argparse.ArgumentParser(
        description="Export Hyper Alpha Arena PostgreSQL databases"
    )
    parser.add_argument(
        "--output-dir",
        default="./db_exports",
        help="Directory to store exported SQL files (default: ./db_exports)"
    )
    
    args = parser.parse_args()
    
    exporter = DatabaseExporter(output_dir=args.output_dir)
    success = exporter.run()
    
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
