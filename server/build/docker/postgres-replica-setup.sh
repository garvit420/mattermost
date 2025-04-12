#!/bin/bash
set -e

# Wait for postgres-primary to be ready
until PGPASSWORD=mostest psql -h postgres-primary -U mmuser -d mattermost_test -c '\q'; do
  >&2 echo "Postgres primary is unavailable - sleeping"
  sleep 1
done

# Create the replication user on primary
PGPASSWORD=mostest psql -h postgres-primary -U mmuser -d mattermost_test -c "CREATE ROLE replicator WITH REPLICATION PASSWORD 'replicator' LOGIN;"

# Configure the replica for replication
cat > /var/lib/postgresql/data/postgresql.conf << EOF
# Replication settings
primary_conninfo = 'host=postgres-primary port=5432 user=replicator password=replicator'
hot_standby = on
EOF

# Create slot on primary if it doesn't exist
PGPASSWORD=mostest psql -h postgres-primary -U mmuser -d mattermost_test -c "SELECT pg_create_physical_replication_slot('replica_slot') ON CONFLICT DO NOTHING;"

# Set up the recovery configuration for the replica
cat > /var/lib/postgresql/data/recovery.conf << EOF
standby_mode = 'on'
primary_conninfo = 'host=postgres-primary port=5432 user=replicator password=replicator'
primary_slot_name = 'replica_slot'
EOF

echo "PostgreSQL replica configuration completed" 