#!/bin/bash

set -e

echo "======================================"
echo "Testing Task API Application"
echo "======================================"
echo ""

BASE_URL="http://localhost"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓ PASS${NC}: $2"
    else
        echo -e "${RED}✗ FAIL${NC}: $2"
        exit 1
    fi
}

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 5

# Test 1: Health Check
echo ""
echo "Test 1: Health Check"
response=$(curl -s -w "\n%{http_code}" ${BASE_URL}/health)
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -eq 200 ]; then
    print_result 0 "Health check endpoint is accessible"
    echo "Response: $body"
else
    print_result 1 "Health check failed with code $http_code"
fi

# Test 2: Create a Task
echo ""
echo "Test 2: Create a Task"
response=$(curl -s -w "\n%{http_code}" -X POST ${BASE_URL}/api/tasks \
    -H "Content-Type: application/json" \
    -d '{"title":"Test Task 1","description":"This is a test task"}')
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -eq 201 ]; then
    print_result 0 "Task created successfully"
    task_id=$(echo "$body" | grep -o '"id":[0-9]*' | grep -o '[0-9]*')
    echo "Created task ID: $task_id"
    echo "Response: $body"
else
    print_result 1 "Task creation failed with code $http_code"
fi

# Test 3: List All Tasks
echo ""
echo "Test 3: List All Tasks"
response=$(curl -s -w "\n%{http_code}" ${BASE_URL}/api/tasks)
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -eq 200 ]; then
    print_result 0 "Tasks listed successfully"
    echo "Response: $body"
else
    print_result 1 "Listing tasks failed with code $http_code"
fi

# Test 4: Get Specific Task
echo ""
echo "Test 4: Get Specific Task"
response=$(curl -s -w "\n%{http_code}" ${BASE_URL}/api/tasks/${task_id})
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -eq 200 ]; then
    print_result 0 "Task retrieved successfully"
    echo "Response: $body"
else
    print_result 1 "Getting task failed with code $http_code"
fi

# Test 5: Update Task
echo ""
echo "Test 5: Update Task"
response=$(curl -s -w "\n%{http_code}" -X PUT ${BASE_URL}/api/tasks/${task_id} \
    -H "Content-Type: application/json" \
    -d '{"title":"Updated Task","completed":true}')
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -eq 200 ]; then
    print_result 0 "Task updated successfully"
    echo "Response: $body"
else
    print_result 1 "Updating task failed with code $http_code"
fi

# Test 6: Cache Test (should hit cache)
echo ""
echo "Test 6: Test Caching"
echo "First request (should populate cache)..."
response1=$(curl -s ${BASE_URL}/api/tasks)
echo "Second request (should hit cache)..."
response2=$(curl -s ${BASE_URL}/api/tasks)

if [ "$response1" == "$response2" ]; then
    print_result 0 "Caching works correctly"
else
    print_result 1 "Caching may not be working"
fi

# Test 7: Delete Task
echo ""
echo "Test 7: Delete Task"
response=$(curl -s -w "\n%{http_code}" -X DELETE ${BASE_URL}/api/tasks/${task_id})
http_code=$(echo "$response" | tail -n 1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -eq 200 ]; then
    print_result 0 "Task deleted successfully"
    echo "Response: $body"
else
    print_result 1 "Deleting task failed with code $http_code"
fi

# Test 8: Verify Deletion
echo ""
echo "Test 8: Verify Deletion"
response=$(curl -s -w "\n%{http_code}" ${BASE_URL}/api/tasks/${task_id})
http_code=$(echo "$response" | tail -n 1)

if [ "$http_code" -eq 404 ]; then
    print_result 0 "Task correctly returns 404 after deletion"
else
    print_result 1 "Task should return 404 but returned $http_code"
fi

echo ""
echo "======================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "======================================"
