#!/usr/bin/env bash
set -euo pipefail

RUN_DOCKER_INTEGRATION=1 swift test --filter IntegrationTests "$@"
