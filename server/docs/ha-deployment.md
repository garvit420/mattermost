# Mattermost High Availability Deployment Guide

This guide provides instructions for setting up a high availability deployment of Mattermost. The setup includes multiple Mattermost nodes, Redis for pub/sub messaging and session storage, PostgreSQL with replication, and S3-compatible object storage for file uploads.

## Architecture

The high availability setup includes the following components:

```
            ┌────────────────────────────┐
            │         Load Balancer       │
            └────────────────────────────┘
                        │
        ┌───────────────┼────────────────┬───────────────┐
        │               │                │               │
 ┌────────────┐   ┌────────────┐   ┌────────────┐   ┌────────────┐
 │ App Server │   │ App Server │   │ App Server │   │ App Server │
 │   Node 1   │   │   Node 2    │   │   Node 3    │   │   Node 4    │
 └────────────┘   └────────────┘   └────────────┘   └────────────┘
        │               │                │               │
 ┌─────────────────────────────────────────────────────────────┐
 │                   Shared Database (Primary/Replica)         │
 └─────────────────────────────────────────────────────────────┘
        │
 ┌─────────────────────────────────────────────────────────────┐
 │                     Redis Pub/Sub Cluster                   │
 └─────────────────────────────────────────────────────────────┘
        │
 ┌─────────────────────────────────────────────────────────────┐
 │             File Storage (Shared NFS / S3-Compatible)        │
 └─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- Enterprise Edition license for Mattermost (required for HA support)
- Docker and Docker Compose installed
- At least 8GB of RAM for running the entire stack

## Quick Start

1. Clone the Mattermost repository:
   ```bash
   git clone https://github.com/mattermost/mattermost.git
   cd mattermost/server
   ```

2. Run the enhanced HA setup with a single command:
   ```bash
   make run-enhanced-haserver
   ```

   This will start:
   - 3 Mattermost nodes (leader, follower, follower2)
   - 1 PostgreSQL primary and 1 replica
   - Redis with 2 replicas
   - MinIO for S3-compatible storage
   - Nginx as a load balancer

3. Access Mattermost at http://localhost:8065

## Manual Configuration

If you prefer to configure Mattermost for HA manually, follow these steps:

### 1. Configure the Database

Mattermost supports MySQL and PostgreSQL databases. For HA, we recommend using PostgreSQL with replication:

```json
"SqlSettings": {
  "DriverName": "postgres",
  "DataSource": "postgres://mmuser:mostest@postgres-primary/mattermost_test?sslmode=disable&connect_timeout=10",
  "DataSourceReplicas": ["postgres://mmuser:mostest@postgres-replica/mattermost_test?sslmode=disable&connect_timeout=10"],
  "MaxIdleConns": 20,
  "MaxOpenConns": 300
}
```

### 2. Enable Clustering

Add the following to your `config.json` file:

```json
"ClusterSettings": {
  "Enable": true,
  "ClusterName": "mattermost-cluster",
  "UseIPAddress": true,
  "ReadOnlyConfig": true,
  "GossipPort": 8074
}
```

### 3. Configure Redis

Redis is used for pub/sub messaging and session storage:

```json
"RedisSettings": {
  "Enable": true,
  "Host": "redis-master:6379",
  "Password": "",
  "Database": 0,
  "CachePrefix": "mattermost_cache:"
}
```

### 4. Configure File Storage

Use S3-compatible storage for file uploads:

```json
"FileSettings": {
  "DriverName": "amazons3",
  "AmazonS3Bucket": "mattermost-uploads",
  "AmazonS3AccessKeyId": "minioaccesskey",
  "AmazonS3SecretAccessKey": "miniosecretkey",
  "AmazonS3Endpoint": "minio:9000",
  "AmazonS3SSL": false
}
```

## Monitoring and Maintenance

### Health Checks

Each Mattermost node exposes a health endpoint at `/api/v4/system/ping` that returns a 200 OK status when the server is healthy. Configure your load balancer to use this endpoint for health checks.

### Logs

Logs are stored in the `logs` directory. Each node has its own log file. You can configure log aggregation tools like Loki and Promtail to collect and analyze logs.

### Metrics

Mattermost provides Prometheus metrics that can be used to monitor the performance and health of the system. Enable metrics in your config:

```json
"MetricsSettings": {
  "Enable": true,
  "ListenAddress": ":8067"
}
```

## Troubleshooting

### Common Issues

1. **Cluster nodes not connecting**: Check that all nodes can reach each other on port 8074 (gossip protocol).

2. **WebSocket disconnections**: Ensure that WebSocket connections are sticky at the load balancer level.

3. **File upload issues**: Verify that all nodes have the same S3 configuration and can access the S3 bucket.

### Helpful Commands

- Check cluster status:
  ```bash
  docker compose -f docker-compose.ha.yml exec leader mmctl --local system status
  ```

- View logs from a specific node:
  ```bash
  docker compose -f docker-compose.ha.yml logs leader
  ```

- Restart a node:
  ```bash
  docker compose -f docker-compose.ha.yml restart follower
  ```

## Scaling Considerations

### Adding More Nodes

To add more Mattermost nodes:

1. Add the new node configuration to `docker-compose.ha.yml`
2. Update the load balancer configuration to include the new node
3. Start the new node: `docker compose -f docker-compose.ha.yml up -d new-node`

### Database Scaling

For high-traffic installations, consider:

- Increasing connection pool sizes in the database settings
- Adding more read replicas
- Implementing database connection poolers like PgBouncer

### Redis Scaling

For large deployments:

- Use Redis Sentinel for automatic failover
- Consider Redis Cluster for horizontal scaling
- Separate cache and session Redis instances

## References

- [Mattermost High Availability Deployment Guide](https://docs.mattermost.com/scale/high-availability-cluster-based-deployment.html)
- [Redis at Scale in Mattermost](https://mattermost.com/blog/lessons-learned-running-redis-at-scale/)
- [Scaling Mattermost for Enterprise](https://docs.mattermost.com/scale/scaling-for-enterprise.html) 