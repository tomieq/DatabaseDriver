#!/usr/bin/env bash
set -euo pipefail

echo "Running integration tests..."
RUN_DOCKER_INTEGRATION=1 swift test -v
