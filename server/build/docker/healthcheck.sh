#!/bin/bash
# Mattermost HA Cluster Health Check Script

# Configuration
MATTERMOST_URL="http://localhost:8065"
REDIS_NODES=("redis-node-0" "redis-node-1" "redis-node-2")
REDIS_PORT="6379"
POSTGRES_PRIMARY="postgres-primary"
POSTGRES_REPLICA="postgres-replica"
POSTGRES_PORT="5432"
MINIO_URL="http://minio:9000"
MATTERMOST_NODES=("leader" "follower" "follower2")

# Output color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to check if a service is reachable
check_service() {
    local host=$1
    local port=$2
    local service_name=$3
    
    nc -z -w 5 $host $port 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] $service_name is reachable${NC}"
        return 0
    else
        echo -e "${RED}[✗] $service_name is unreachable${NC}"
        return 1
    fi
}

# Function to check Redis Cluster status
check_redis_cluster() {
    local primary_node=$1
    
    if ! check_service $primary_node $REDIS_PORT "Redis Node ($primary_node)"; then
        return 1
    fi
    
    # Check cluster status
    local cluster_state=$(redis-cli -h $primary_node CLUSTER INFO | grep cluster_state | cut -d':' -f2 | tr -d '\r')
    if [ "$cluster_state" == "ok" ]; then
        echo -e "${GREEN}[✓] Redis Cluster state is OK${NC}"
        
        # Check number of nodes
        local cluster_size=$(redis-cli -h $primary_node CLUSTER NODES | wc -l)
        echo -e "${GREEN}[✓] Redis Cluster size: $cluster_size nodes${NC}"
        
        return 0
    else
        echo -e "${RED}[✗] Redis Cluster is not in 'ok' state ($cluster_state)${NC}"
        return 1
    fi
}

# Function to check Mattermost health
check_mattermost() {
    curl -s -o /dev/null -w "%{http_code}" $MATTERMOST_URL/api/v4/system/ping 2>/dev/null | grep -q "200"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] Mattermost is responding to health checks${NC}"
        return 0
    else
        echo -e "${RED}[✗] Mattermost is not responding to health checks${NC}"
        return 1
    fi
}

# Function to check PostgreSQL health
check_postgres() {
    local host=$1
    local user="mmuser"
    local db="mattermost_test"
    
    if ! check_service $host $POSTGRES_PORT "PostgreSQL ($host)"; then
        return 1
    fi
    
    # Check if psql is available
    which psql > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}[!] psql not found. Cannot perform advanced PostgreSQL checks${NC}"
        return 0
    fi
    
    # Try to connect to the database
    PGPASSWORD=mostest psql -h $host -U $user -d $db -c "SELECT 1" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] PostgreSQL ($host) connection successful${NC}"
        return 0
    else
        echo -e "${RED}[✗] Cannot connect to PostgreSQL ($host) database${NC}"
        return 1
    fi
}

# Function to check MinIO health
check_minio() {
    curl -s -o /dev/null -w "%{http_code}" $MINIO_URL/minio/health/live 2>/dev/null | grep -q "200"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] MinIO is healthy${NC}"
        return 0
    else
        echo -e "${RED}[✗] MinIO is not responding to health checks${NC}"
        return 1
    fi
}

# Function to check Mattermost node health
check_mattermost_node() {
    local node=$1
    
    if ! check_service $node 8065 "Mattermost node ($node)"; then
        return 1
    fi
    
    # Check node health via API
    curl -s -o /dev/null -w "%{http_code}" http://$node:8065/api/v4/system/ping 2>/dev/null | grep -q "200"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] Mattermost node ($node) is healthy${NC}"
        return 0
    else
        echo -e "${RED}[✗] Mattermost node ($node) is not responding to health checks${NC}"
        return 1
    fi
}

# Main health check
echo "===================================="
echo "Mattermost HA Cluster Health Check"
echo "===================================="
echo ""

echo "Checking Redis Cluster..."
check_redis_cluster ${REDIS_NODES[0]}
echo ""

echo "Checking PostgreSQL..."
check_postgres $POSTGRES_PRIMARY
check_postgres $POSTGRES_REPLICA
echo ""

echo "Checking MinIO..."
check_minio
echo ""

echo "Checking Mattermost nodes..."
for node in "${MATTERMOST_NODES[@]}"; do
    check_mattermost_node $node
done
echo ""

echo "Checking overall Mattermost service..."
check_mattermost
echo ""

echo "===================================="
echo "Health check completed"
echo "====================================" 