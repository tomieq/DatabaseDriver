#!/usr/bin/env bash
set -euo pipefail

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)

CID=$($SCRIPTDIR/run_mysql_container.sh)
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT

echo "Running integration tests..."
RUN_DOCKER_INTEGRATION=1 swift test -v
