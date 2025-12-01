Workflow to Transfer Database:

On current device (Mac):

./exportdb.sh
# Copy db_exports/latest.sql to other device

On new device:


# Make sure PostgreSQL is running and user/database are set up
./importdb.sh ./db_exports/latest.sql
# Type "yes" to confirm

Start development on new device:

pnpm local