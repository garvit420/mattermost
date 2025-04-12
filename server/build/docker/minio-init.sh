#!/bin/bash
set -e

# Install mc client to interact with MinIO
wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
until nc -z minio 9000; do
  sleep 1
done
sleep 5  # Give a bit more time for the service to fully initialize

# Configure mc client
mc config host add minio http://minio:9000 minioaccesskey miniosecretkey

# Create buckets if they don't exist
echo "Creating mattermost-uploads bucket..."
mc mb --ignore-existing minio/mattermost-uploads

# Set bucket policy to allow public read access (optional, adjust based on your security needs)
echo "Setting bucket policies..."
mc policy set download minio/mattermost-uploads

echo "MinIO initialization completed successfully" 