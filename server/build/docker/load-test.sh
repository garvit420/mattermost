#!/bin/bash
# Mattermost HA Cluster Load Testing Script

set -e

# Configuration
MATTERMOST_URL="http://localhost:8065"
TEST_DURATION=300  # 5 minutes
CONCURRENT_USERS=50
RAMP_UP_TIME=60  # seconds
TEST_RESULT_DIR="./load-test-results"

# Ensure k6 is installed
if ! command -v k6 &> /dev/null; then
    echo "k6 is not installed. Please install it first (https://k6.io/docs/getting-started/installation/)"
    exit 1
fi

# Create test result directory
mkdir -p $TEST_RESULT_DIR

# Create temporary k6 script
cat > /tmp/mattermost-load-test.js << 'EOF'
import http from 'k6/http';
import { sleep, check } from 'k6';
import { SharedArray } from 'k6/data';
import { randomIntBetween } from 'k6/utils';

// Configuration from environment variables
const BASE_URL = __ENV.MATTERMOST_URL || 'http://localhost:8065';

// Test users data (predefined for simplicity)
const users = new SharedArray('users', function() {
  return [
    { username: 'testuser1', password: 'password123', email: 'testuser1@example.com' },
    { username: 'testuser2', password: 'password123', email: 'testuser2@example.com' },
    { username: 'testuser3', password: 'password123', email: 'testuser3@example.com' },
    // Add more users as needed
  ];
});

// Test data
const channels = [
  { name: 'general', team: 'test-team' },
  { name: 'random', team: 'test-team' },
  // Add more channels as needed
];

const messages = [
  'Hello everyone!',
  'How are you doing today?',
  'This is a test message for load testing.',
  'Mattermost high availability is awesome!',
  'Just checking if this works across all nodes.',
  'Testing real-time message delivery in a cluster.',
  'Does anyone see this message?',
  'Horizontal scaling FTW!',
  'This message should appear on all nodes immediately.',
  'Testing, testing, 1, 2, 3...',
];

// K6 test configuration
export const options = {
  stages: [
    { duration: '1m', target: __ENV.CONCURRENT_USERS || 50 }, // Ramp up
    { duration: '3m', target: __ENV.CONCURRENT_USERS || 50 }, // Stay at peak load
    { duration: '1m', target: 0 },                            // Ramp down
  ],
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests must complete within 500ms
    'http_req_duration{name:login}': ['p(95)<1000'],
    'http_req_duration{name:send_message}': ['p(95)<800'],
    'http_req_duration{name:get_channels}': ['p(95)<600'],
  },
};

// Login function
function login(user) {
  const payload = JSON.stringify({
    login_id: user.username,
    password: user.password
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
    tags: { name: 'login' },
  };

  const loginRes = http.post(`${BASE_URL}/api/v4/users/login`, payload, params);
  
  check(loginRes, {
    'logged in successfully': (resp) => resp.status === 200,
  });

  return loginRes.headers.Token || loginRes.headers.token;
}

// Get channels function
function getChannels(token, teamId) {
  const params = {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    tags: { name: 'get_channels' },
  };

  const channelsRes = http.get(`${BASE_URL}/api/v4/users/me/teams/${teamId}/channels`, params);
  
  check(channelsRes, {
    'got channels successfully': (resp) => resp.status === 200,
  });

  return JSON.parse(channelsRes.body);
}

// Send message function
function sendMessage(token, channelId, message) {
  const payload = JSON.stringify({
    channel_id: channelId,
    message: message,
  });

  const params = {
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    tags: { name: 'send_message' },
  };

  const postRes = http.post(`${BASE_URL}/api/v4/posts`, payload, params);
  
  check(postRes, {
    'message sent successfully': (resp) => resp.status === 201,
  });

  return JSON.parse(postRes.body);
}

// Main test function
export default function() {
  // Select a random user
  const user = users[randomIntBetween(0, users.length - 1)];
  
  // Login
  const token = login(user);
  if (!token) return;
  
  // Simulate user browsing channels and sending messages
  for (let i = 0; i < randomIntBetween(3, 8); i++) {
    // Get team ID (hardcoded for simplicity - would be retrieved dynamically in real test)
    const teamId = 'team1';  // This should be retrieved or created in setup
    
    // Get channels
    const channels = getChannels(token, teamId);
    if (!channels || channels.length === 0) continue;
    
    // Select random channel
    const channel = channels[randomIntBetween(0, channels.length - 1)];
    
    // Send a random message
    const message = messages[randomIntBetween(0, messages.length - 1)];
    sendMessage(token, channel.id, message);
    
    // Simulate reading messages (would fetch recent posts in real test)
    sleep(randomIntBetween(1, 5));
  }
  
  // Simulate user thinking time
  sleep(randomIntBetween(3, 10));
}

// Optional: setup and teardown for creating test data
export function setup() {
  // Would create test team, channels, and users here in a real test
  console.log('Test setup complete');
}

export function teardown(data) {
  // Would clean up test data here in a real test
  console.log('Test teardown complete');
}
EOF

echo "Starting load test on Mattermost HA Cluster..."
echo "URL: $MATTERMOST_URL"
echo "Duration: $TEST_DURATION seconds"
echo "Concurrent Users: $CONCURRENT_USERS"

# Run the load test
k6 run \
  --env MATTERMOST_URL=$MATTERMOST_URL \
  --env CONCURRENT_USERS=$CONCURRENT_USERS \
  --out json=$TEST_RESULT_DIR/results.json \
  --summary-export=$TEST_RESULT_DIR/summary.json \
  /tmp/mattermost-load-test.js

echo "Load test completed. Results saved to $TEST_RESULT_DIR"
echo "Analyzing results..."

# Basic results analysis
if [ -f "$TEST_RESULT_DIR/summary.json" ]; then
  TOTAL_REQUESTS=$(jq '.metrics.http_reqs.values.count' $TEST_RESULT_DIR/summary.json)
  AVG_RESPONSE_TIME=$(jq '.metrics.http_req_duration.values.avg' $TEST_RESULT_DIR/summary.json)
  P95_RESPONSE_TIME=$(jq '.metrics.http_req_duration.values["p(95)"]' $TEST_RESULT_DIR/summary.json)
  ERROR_RATE=$(jq '.metrics.http_req_failed.values.rate' $TEST_RESULT_DIR/summary.json)
  
  echo ""
  echo "=== Load Test Summary ==="
  echo "Total Requests: $TOTAL_REQUESTS"
  echo "Average Response Time: $AVG_RESPONSE_TIME ms"
  echo "95th Percentile Response Time: $P95_RESPONSE_TIME ms"
  echo "Error Rate: $ERROR_RATE %"
  echo ""
  
  # Check if error rate exceeds threshold
  if (( $(echo "$ERROR_RATE > 0.05" | bc -l) )); then
    echo "ALERT: Error rate exceeds threshold of 5%"
  else
    echo "Success: Error rate is within acceptable limits"
  fi
  
  # Check if response time exceeds threshold
  if (( $(echo "$P95_RESPONSE_TIME > 500" | bc -l) )); then
    echo "ALERT: 95th percentile response time exceeds threshold of 500ms"
  else
    echo "Success: Response time is within acceptable limits"
  fi
fi

echo ""
echo "Load test analysis complete" 