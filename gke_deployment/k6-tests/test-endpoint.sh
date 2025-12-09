#!/bin/bash
# Quick test script to check what the register endpoint actually returns

BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "Testing: ${BASE_URL}/wrk2-api/user/register"
echo ""

# Generate a unique user
USER_ID=$((RANDOM % 1000000))
TIMESTAMP=$(date +%s)
USERNAME="testuser_${USER_ID}_${TIMESTAMP}"

echo "User ID: ${USER_ID}"
echo "Username: ${USERNAME}"
echo ""

# Test the endpoint
RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST "${BASE_URL}/wrk2-api/user/register" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "user_id=${USER_ID}&username=${USERNAME}&first_name=Test&last_name=User&password=testpass123")

# Extract status code and body
BODY=$(echo "$RESPONSE" | sed '/HTTP_STATUS:/d')
STATUS=$(echo "$RESPONSE" | grep "HTTP_STATUS:" | cut -d: -f2)

echo "Response Status: ${STATUS}"
echo "Response Body: ${BODY}"
echo ""

if [ "$STATUS" = "200" ]; then
  echo "✅ SUCCESS: Endpoint returned 200 OK"
else
  echo "❌ FAILURE: Endpoint returned ${STATUS}"
  echo "This explains why k6 is seeing 100% failure rate"
fi

