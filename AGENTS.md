Simple pure Swift MySQL/MariaDB driver to make working with databases easier.
Implemented as full Swift 6 structured concurrecy to work on MacOS, iOS and Linux platforms.

## Testing instructions
Local MacOS machine has docker running with images: mysql:9.7.0 and swift:6.1
- Run `swift tests` for unit test on local MacOS
- Run `RUN_DOCKER_INTEGRATION=1 swift test --filter IntegrationTests` for integration test on local MacOS; the test will start its own MySQL container on `127.0.0.1:3307`
- Run: `docker run --rm -t  -v "$PWD":/workspace -w /workspace swift:6.1  swift test` for unit test on linux
- For linux integration tests with Swift and MySQL in the same Docker network run commands:
```
docker network create dbdriver-test-net
docker run -d --rm \
  --name dbdriver-mysql \
  --network dbdriver-test-net \
  -e MYSQL_ALLOW_EMPTY_PASSWORD=yes \
  mysql:9.7.0
docker run --rm -t \
  --network dbdriver-test-net \
  -v "$PWD":/workspace \
  -w /workspace \
  -e RUN_DOCKER_INTEGRATION=1 \
  -e DB_HOST=dbdriver-mysql \
  -e DB_PORT=3306 \
  swift:6.1 \
  swift test --filter IntegrationTests
```
When `DB_HOST` is set, integration tests use that database instead of starting their own container. Optional overrides: `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_DOCKER_IMAGE`, `DB_CONTAINER_NAME`.
## Change commit
Never commit anything, let user review changes.
