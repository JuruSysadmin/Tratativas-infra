#!/usr/bin/env bash
set -euo pipefail

# SonarQube analysis script for Chat project
# Usage: ./ci/sonar.sh

SONAR_HOST="${SONAR_HOST:-http://localhost:9001}"
SONAR_TOKEN="${SONAR_TOKEN:-sqp_dee05c6d3e216c40cac17dcd2392e4dd614b4d57}"

echo "=== SonarQube Analysis ==="
echo "Host: $SONAR_HOST"
echo "Project: Chat"
echo ""

# Step 1: Get dependencies
echo "==> Getting dependencies..."
mix deps.get --only test 2>&1

# Step 2: Run tests with coverage
echo "==> Running tests with coverage..."
MIX_ENV=test mix coveralls.xml 2>&1

# Step 3: Run SonarScanner
echo "==> Running SonarScanner..."
sonar-scanner \
  -Dsonar.projectKey=Chat \
  -Dsonar.sources=lib \
  -Dsonar.tests=test \
  -Dsonar.host.url="$SONAR_HOST" \
  -Dsonar.token="$SONAR_TOKEN" \
  -Dsonar.exclusions="deps/**,_build/**,assets/**,rel/**,priv/**,node_modules/**,.elixir_ls/**,cover/**,.scannerwork/**" 2>&1

echo ""
echo "=== Analysis complete ==="
echo "View results at: $SONAR_HOST/dashboard?id=Chat"
