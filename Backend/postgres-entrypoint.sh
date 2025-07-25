#!/bin/bash

# Set environment variables for psql and pg_restore
export PGPASSWORD="$POSTGRES_PASSWORD"

# Run the default PostgreSQL entrypoint in the background
/usr/local/bin/docker-entrypoint.sh postgres &

# Wait for PostgreSQL to be ready (retry up to 30 times, 2s delay)
for i in {1..30}; do
  if pg_isready -U "$POSTGRES_USER" -h localhost -p 5432 -d postgres; then
    echo "PostgreSQL is ready"
    break
  fi
  echo "Waiting for PostgreSQL to be ready... (attempt $i/30)"
  sleep 2
done

if ! pg_isready -U "$POSTGRES_USER" -h localhost -p 5432 -d postgres; then
  echo "PostgreSQL failed to start"
  exit 1
fi

# Create the database if it doesn't exist
psql -U "$POSTGRES_USER" -h localhost -p 5432 -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$POSTGRES_USER\";" 2>/dev/null || echo "Database $POSTGRES_DB already exists"

# Check for backup files in /var/backups
BACKUP_DIR="/var/backups"
DB_NAME="us_stock_options_db"
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/${DB_NAME}_*.dump 2>/dev/null | head -n 1)

if [ -n "$LATEST_BACKUP" ]; then
  echo "Found latest backup: $LATEST_BACKUP"
  # Restore the backup with --clean to drop existing tables
  pg_restore -U "$POSTGRES_USER" -h localhost -p 5432 -d "$POSTGRES_DB" --clean --if-exists --verbose "$LATEST_BACKUP"
  if [ $? -eq 0 ]; then
    echo "Successfully restored backup: $LATEST_BACKUP"
  else
    echo "Failed to restore backup: $LATEST_BACKUP"
    exit 1
  fi
else
  echo "No backup found in $BACKUP_DIR"
  # Apply init-db.sql only if no backup is restored
  if [ -f "/docker-entrypoint-initdb.d/init-db.sql" ]; then
    echo "Applying init-db.sql..."
    psql -U "$POSTGRES_USER" -h localhost -p 5432 -d "$POSTGRES_DB" -f /docker-entrypoint-initdb.d/init-db.sql
  fi
fi

# Keep the container running
wait