#!/usr/bin/env bash
set -euo pipefail

NETWORK=${DB_DOCKER_NETWORK:-dbdriver-test-net}
MYSQL_CONTAINER=${DB_CONTAINER_NAME:-dbdriver-mysql}
SWIFT_CONTAINER=${DB_SWIFT_CONTAINER_NAME:-dbdriver-swift-test}
MYSQL_IMAGE=${DB_DOCKER_IMAGE:-mysql:9.7.0}
SWIFT_IMAGE=${SWIFT_DOCKER_IMAGE:-swift:6.1}
DB_USER=${DB_USER:-root}
DB_PASSWORD=${DB_PASSWORD:-}

cleanup() {
  docker rm -f "$SWIFT_CONTAINER" "$MYSQL_CONTAINER" >/dev/null 2>&1 || true
  docker network rm "$NETWORK" >/dev/null 2>&1 || true
}

cleanup
trap cleanup EXIT

docker network create "$NETWORK" >/dev/null
docker run -d --rm \
  --name "$MYSQL_CONTAINER" \
  --network "$NETWORK" \
  -e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
  "$MYSQL_IMAGE" >/dev/null

echo "Waiting for MySQL to become ready..." >&2
until docker exec "$MYSQL_CONTAINER" mysqladmin ping -h 127.0.0.1 -u"$DB_USER" --silent; do
  sleep 1
done

docker run --rm -t \
  --name "$SWIFT_CONTAINER" \
  --network "$NETWORK" \
  -v "$PWD":/workspace \
  -w /workspace \
  -e RUN_DOCKER_INTEGRATION=1 \
  -e DB_HOST="$MYSQL_CONTAINER" \
  -e DB_PORT=3306 \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  "$SWIFT_IMAGE" \
  swift test --filter IntegrationTests "$@"