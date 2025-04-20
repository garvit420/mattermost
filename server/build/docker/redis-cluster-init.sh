#!/bin/bash
set -e

# Wait for Redis nodes to be ready
echo "Waiting for Redis nodes to be ready..."
until redis-cli -h redis-node-0 PING; do
  echo "redis-node-0 is unavailable - sleeping"
  sleep 1
done

until redis-cli -h redis-node-1 PING; do
  echo "redis-node-1 is unavailable - sleeping"
  sleep 1
done

until redis-cli -h redis-node-2 PING; do
  echo "redis-node-2 is unavailable - sleeping"
  sleep 1
done

# Create Redis cluster if it doesn't already exist
if ! redis-cli -h redis-node-0 CLUSTER INFO | grep -q "cluster_state:ok"; then
  echo "Creating Redis cluster..."
  redis-cli --cluster create redis-node-0:6379 redis-node-1:6379 redis-node-2:6379 --cluster-replicas 0 --cluster-yes
  
  echo "Verifying cluster state..."
  redis-cli -h redis-node-0 CLUSTER INFO
  
  # Create some test data to ensure the cluster is working
  echo "Testing cluster connectivity..."
  redis-cli -c -h redis-node-0 SET mattermost_test_key "Cluster initialized successfully"
  test_value=$(redis-cli -c -h redis-node-1 GET mattermost_test_key)
  
  if [ "$test_value" == "Cluster initialized successfully" ]; then
    echo "Redis cluster is functioning correctly"
  else
    echo "WARNING: Cluster test failed. Cluster may not be working properly."
    exit 1
  fi
else
  echo "Redis cluster is already running"
  redis-cli -h redis-node-0 CLUSTER INFO | grep cluster_state
fi

echo "Redis cluster initialization completed" 