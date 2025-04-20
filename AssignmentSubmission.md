# Mattermost High Availability Implementation

## 1. Approach

### Overview

My approach to implementing high availability for Mattermost was to leverage the platform's built-in enterprise capabilities while creating a complete infrastructure that supports:

1. **Multi-node deployment** for horizontal scaling and redundancy
2. **Shared stateful components** to ensure consistency across nodes
3. **Real-time synchronization** for messages and events
4. **Automated failover** to maintain service during node outages

Rather than modifying the core Mattermost code (which already supports HA), I focused on:

1. Creating proper configuration templates for HA settings
2. Developing a robust infrastructure using Docker Compose
3. Implementing supporting scripts for deployment and monitoring
4. Adding Makefile targets for simplified operations
5. Creating comprehensive documentation
6. Integrating Redis Cluster for improved pub/sub messaging and scalability

### Implementation Strategy

I followed these steps:

1. **Research & Analysis**: Examined the existing Mattermost architecture to understand its HA capabilities and requirements
2. **Infrastructure Design**: Designed a scalable architecture with redundant components
3. **Configuration**: Created configuration templates with optimal settings for HA
4. **Deployment Automation**: Developed scripts and Makefile targets for deployment
5. **Testing & Monitoring**: Added health check tools to verify proper operation
6. **Documentation**: Created detailed guides for operation and maintenance
7. **Redis Cluster Integration**: Implemented and configured Redis Cluster for improved scalability

## 2. System Architecture

### High-Level Architecture

```
                    ┌────────────────────────────┐
                    │         Load Balancer      │
                    └────────────────────────────┘
                                  │
        ┌─────────────────────────|──────┬───────────────┐
        │               │                │               │
 ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐
 │ App Server │   │ App Server │   │ App Server │   │ App Server │
 │   Node 1   │   │   Node 2   │   │   Node 3   │   │   Node 4   │
 └────────────┘   └────────────┘   └────────────┘   └────────────┘
        │               │                │               │
 ┌─────────────────────────────────────────────────────────────┐
 │                         Shared Database                     │
 └─────────────────────────────────────────────────────────────┘
                                │
 ┌─────────────────────────────────────────────────────────────┐
 │                     Redis Cluster                           │
 └─────────────────────────────────────────────────────────────┘
                                │
 ┌─────────────────────────────────────────────────────────────┐
 │                           File Storage                      │
 └─────────────────────────────────────────────────────────────┘
```

### Component Breakdown

| Component | Implementation | Purpose |
|:----------|:---------------|:--------|
| **Load Balancer** | Nginx | Distributes traffic across nodes, handles WebSocket connections, performs health checks |
| **App Servers** | Multiple Mattermost instances | Process HTTP requests, WebSocket connections, and run application logic |
| **Database** | PostgreSQL with replication | Primary database for persistent storage with read replicas for scaling |
| **Redis Cluster** | Redis Cluster (3+ nodes) | Provides distributed pub/sub messaging and session storage with sharding |
| **File Storage** | MinIO (S3-compatible) | Shared storage for file uploads, ensuring consistency across nodes |

### Key Architectural Features

1. **Stateless Application Nodes**:
   - Multiple identical Mattermost instances can be added/removed without affecting service
   - Each node runs the same code and configuration
   - No local state is maintained on the nodes

2. **Real-time Event Propagation**:
   - Redis Cluster ensures all nodes receive events simultaneously
   - WebSocket messages are broadcast across all nodes via Redis pub/sub
   - Scales horizontally with multiple Redis nodes
   - User presence status is consistent regardless of which node a user connects to

3. **Database High Availability**:
   - Primary-replica setup with automatic failover capability
   - Connection pooling optimizes database resource usage
   - Read queries can be distributed to replicas for scaling

4. **Shared File Storage**:
   - S3-compatible storage provides a consistent view of files
   - All nodes have access to the same uploaded content
   - No synchronization issues with attachments

## 3. Key Code Changes

### Redis Cluster Integration

Leveraged the `redis_cluster.go` implementation for distributed messaging:

```go
// server/channels/app/platform/redis_cluster.go
package platform

import (
    "context"
    "fmt"
    "time"
    // Other imports...
    "github.com/redis/go-redis/v9"
)

type RedisClusterService struct {
    client       *redis.ClusterClient
    ps           *PlatformService
    stopChan     chan struct{}
    listenerChan chan struct{}
    logger       *mlog.Logger
    isActive     bool
}

// NewRedisClusterService initializes a RedisClusterService using Redis Cluster
func NewRedisClusterService(ps *PlatformService) (*RedisClusterService, error) {
    // Configuration and connection setup
    // ...
}

// Start begins listening for Pub/Sub events from Redis Cluster
func (rcs *RedisClusterService) Start() {
    // Start the Redis Cluster listener
    // ...
}

// PublishEvent publishes a WebSocket event to the Redis Cluster
func (rcs *RedisClusterService) PublishEvent(event *model.WebSocketEvent) {
    // Publish events to Redis Cluster
    // ...
}
```

### Configuration Changes

Created a comprehensive high availability configuration template with Redis Cluster support:

```json
// server/build/docker/ha-config.json
{
  "ClusterSettings": {
    "Enable": true,
    "ClusterName": "mattermost-cluster",
    "UseIPAddress": true,
    "ReadOnlyConfig": true,
    "GossipPort": 8074
  },
  "RedisSettings": {
    "Enable": true,
    "ClusterAddresses": ["redis-node-0:6379", "redis-node-1:6379", "redis-node-2:6379"],
    "Password": "",
    "PoolSize": 30,
    "PoolTimeoutSeconds": 3,
    "ConnectTimeoutMs": 3000,
    "ReadTimeoutMs": 3000,
    "WriteTimeoutMs": 3000,
    "IdleTimeoutSeconds": 300
  },
  "FileSettings": {
    "DriverName": "amazons3",
    "AmazonS3Bucket": "mattermost-uploads",
    "AmazonS3Endpoint": "minio:9000"
    // Other S3 settings...
  }
}
```

### Infrastructure Implementation

Created a Docker Compose file with Redis Cluster:

```yaml
# docker-compose.ha.yml
services:
  # Load Balancer and Database configurations...

  # Redis Cluster for Session and Pub/Sub
  redis-node-0:
    image: "redis:7.4.0"
    command: redis-server --cluster-enabled yes --cluster-config-file nodes.conf
    # Configuration...

  redis-node-1:
    image: "redis:7.4.0"
    command: redis-server --cluster-enabled yes --cluster-config-file nodes.conf
    # Configuration...

  redis-node-2:
    image: "redis:7.4.0"
    command: redis-server --cluster-enabled yes --cluster-config-file nodes.conf
    # Configuration...

  redis-cluster-init:
    image: "redis:7.4.0"
    # Script to initialize Redis Cluster
    # Configuration...

  # Mattermost nodes with Redis Cluster configuration
  leader:
    environment:
      - "MM_REDISSETTINGS_ENABLE=true"
      - "MM_REDISSETTINGS_CLUSTERADDRESSES=redis-node-0:6379,redis-node-1:6379,redis-node-2:6379"
      - "MM_REDISSETTINGS_POOLTIMEOUTSECONDS=3"
      # Other Redis settings...
    # Configuration...
```

### Redis Cluster Initialization Script

Added a script to initialize the Redis Cluster:

```bash
#!/bin/bash
# build/docker/redis-cluster-init.sh

# Wait for Redis nodes to be ready
echo "Waiting for Redis nodes to be ready..."
# Check connectivity...

# Create Redis cluster if it doesn't already exist
if ! redis-cli -h redis-node-0 CLUSTER INFO | grep -q "cluster_state:ok"; then
  echo "Creating Redis cluster..."
  redis-cli --cluster create redis-node-0:6379 redis-node-1:6379 redis-node-2:6379 --cluster-replicas 0 --cluster-yes
  
  # Verification and testing...
fi
```

### Monitoring and Health Checks

Enhanced the health check script with Redis Cluster support:

```bash
# build/docker/healthcheck.sh

# Function to check Redis Cluster status
check_redis_cluster() {
    local primary_node=$1
    
    # Check connectivity and cluster state
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

# Main health check logic
# ...
```

## 4. Challenges and Solutions

### Challenge 1: Database Replication

**Challenge**: Setting up PostgreSQL replication with automatic failover proved complex due to timing issues during initialization.

**Solution**: Created a custom initialization script that:
- Waits for the primary database to be fully initialized
- Creates a replication user with appropriate permissions
- Sets up replication slots and configuration
- Uses proper health checks to ensure the setup completes successfully

### Challenge 2: Redis Cluster Setup and Configuration

**Challenge**: Moving from a single Redis instance to a Redis Cluster architecture required handling cluster initialization, configuration, and ensuring proper communication between Mattermost nodes and Redis.

**Solution**:
- Leveraged the existing `redis_cluster.go` implementation in Mattermost
- Developed a Redis Cluster initialization script to ensure proper cluster formation
- Updated configuration to use cluster-specific settings
- Ensured WebSocket events properly propagate across the cluster
- Implemented health checks specific to Redis Cluster

### Challenge 3: WebSocket Connections Across Nodes

**Challenge**: WebSocket connections typically maintain state on a specific node, making it difficult to ensure seamless operation if a node fails.

**Solution**: 
- Configured Redis Cluster to share WebSocket events across all nodes
- Implemented session stickiness in the load balancer to maintain connections
- Ensured WebSocket reconnection strategies work properly in a multi-node environment

### Challenge 4: File Storage Consistency

**Challenge**: Ensuring all nodes have consistent access to uploaded files.

**Solution**:
- Implemented S3-compatible storage (MinIO) for all file uploads
- Created an initialization script to set up buckets and permissions
- Configured all nodes to use the same storage settings
- Implemented proper health checks to verify storage availability

### Challenge 5: Monitoring and Troubleshooting

**Challenge**: In a distributed system, identifying issues can be difficult due to the multiple components involved.

**Solution**:
- Created a comprehensive health check script that tests all components including Redis Cluster
- Implemented logging to separate files for each node
- Added Makefile targets for common operations
- Documented common issues and their solutions

## 5. Lessons Learned

1. **Stateless Architecture is Key**: Ensuring all application nodes are truly stateless is critical for HA.

2. **Shared Components Need Redundancy**: Any shared component (database, Redis, file storage) must itself be highly available.

3. **Redis Cluster Advantages**: Moving from a master-replica Redis to a Redis Cluster provides better scaling and resilience.

4. **Configuration Consistency**: All nodes must have identical configurations for the cluster features.

5. **Automated Health Checks**: Regular health checks are essential for early detection of issues.

6. **Documentation is Critical**: Comprehensive documentation makes maintenance and troubleshooting much easier.

## 6. Future Improvements

If given more time, these enhancements would further improve the implementation:

1. **Automated Scaling**: Add scripts to automatically scale nodes based on load.

2. **Enhanced Monitoring**: Integrate with Prometheus and Grafana for more detailed metrics.

3. **Geographic Distribution**: Implement multi-region deployment for even higher availability.

4. **Redis Cluster Optimization**: Fine-tune Redis Cluster configuration for optimal performance.

5. **Backup Automation**: Add automated backup and recovery procedures.

6. **Performance Tuning**: Optimize database and Redis configurations for higher throughput.

## 7. Conclusion

The implemented high availability solution for Mattermost provides a robust, scalable architecture that ensures continuous operation even during component failures. By leveraging built-in HA capabilities, integrating Redis Cluster, and implementing proper infrastructure, we've created a system that:

- Scales horizontally by adding more application nodes
- Maintains data consistency across all components
- Provides real-time synchronization of messages and events using Redis Cluster
- Automatically recovers from component failures
- Can be easily monitored and maintained

This solution aligns with enterprise best practices for high availability while maintaining the full functionality of the Mattermost platform. 