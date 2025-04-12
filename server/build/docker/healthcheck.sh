#!/bin/bash
# Mattermost HA Cluster Health Check Script

# Configuration
MATTERMOST_URL="http://localhost:8065"
REDIS_HOST="redis-master"
REDIS_PORT="6379"
POSTGRES_HOST="postgres-primary"
POSTGRES_PORT="5432"
MINIO_URL="http://minio:9000"
NODES=("leader" "follower" "follower2")

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

# Function to check Mattermost node health
check_mattermost_node() {
    local node=$1
    local url="http://$node:8065/api/v4/system/ping"
    
    curl -s -f $url > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] Mattermost node $node is healthy${NC}"
        return 0
    else
        echo -e "${RED}[✗] Mattermost node $node is unhealthy${NC}"
        return 1
    fi
}

# Function to check Redis replication status
check_redis_replication() {
    echo "Checking Redis replication status..."
    redis-cli -h $REDIS_HOST -p $REDIS_PORT info replication | grep -E "role|connected_slaves|slave0|slave1"
    if redis-cli -h $REDIS_HOST -p $REDIS_PORT info replication | grep -q "role:master"; then
        echo -e "${GREEN}[✓] Redis master is functioning${NC}"
    else
        echo -e "${RED}[✗] Redis master issue detected${NC}"
    fi
}

# Function to check PostgreSQL replication status
check_postgres_replication() {
    echo "Checking PostgreSQL replication status..."
    PGPASSWORD=mostest psql -h $POSTGRES_HOST -U mmuser -d mattermost_test -c "SELECT * FROM pg_stat_replication;" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] PostgreSQL replication is configured${NC}"
    else
        echo -e "${RED}[✗] PostgreSQL replication issue detected${NC}"
    fi
}

# Function to check MinIO health
check_minio_health() {
    curl -s -f $MINIO_URL/minio/health/live > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] MinIO is healthy${NC}"
        return 0
    else
        echo -e "${RED}[✗] MinIO is unhealthy${NC}"
        return 1
    fi
}

# Function to check Mattermost cluster status
check_mattermost_cluster() {
    echo "Checking Mattermost cluster status..."
    docker compose -f docker-compose.ha.yml exec leader mmctl --local system status 2>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[✓] Mattermost cluster appears to be functioning${NC}"
    else
        echo -e "${YELLOW}[!] Could not retrieve Mattermost cluster status${NC}"
    fi
}

# Main health check logic
echo "================================="
echo " Mattermost HA Cluster Health Check"
echo "================================="
echo ""

echo "Checking core services..."
check_service $REDIS_HOST $REDIS_PORT "Redis"
check_service $POSTGRES_HOST $POSTGRES_PORT "PostgreSQL"
check_minio_health

echo ""
echo "Checking Mattermost nodes..."
for node in "${NODES[@]}"; do
    check_mattermost_node $node
done

echo ""
echo "Checking replication status..."
check_redis_replication
check_postgres_replication

echo ""
echo "Checking cluster status..."
check_mattermost_cluster

echo ""
echo "================================="
echo " Health Check Complete"
echo "=================================" 