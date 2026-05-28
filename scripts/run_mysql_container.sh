#!/usr/bin/env bash
set -euo pipefail

NAME=${DB_CONTAINER_NAME:-mysql_integration}
IMAGE=${DB_DOCKER_IMAGE:-mysql:9.7.0}
PORT=${DB_PORT:-3307}
NETWORK=${DB_NETWORK:-}

# Remove any existing container with the same name
docker rm -f "$NAME" >/dev/null 2>&1 || true

docker_args=(run -d --name "$NAME" -e MYSQL_ALLOW_EMPTY_PASSWORD=yes)
if [[ -n "$NETWORK" ]]; then
  docker_args+=(--network "$NETWORK")
else
  docker_args+=(-p "${PORT}:3306")
fi
docker_args+=("$IMAGE")

CID=$(docker "${docker_args[@]}")

echo "Waiting for MySQL to become ready (timeout 90s)..." >&2
timeout=90
elapsed=0
while true; do
  if docker logs "$CID" 2>&1 | grep -q "ready for connections"; then
    echo "MySQL ready" >&2
    break
  fi
  sleep 1
  elapsed=$((elapsed+1))
  if [ "$elapsed" -ge "$timeout" ]; then
    echo "MySQL did not become ready within $timeout seconds" >&2
    docker logs "$CID" || true
    exit 2
  fi
done

echo "$CID"
