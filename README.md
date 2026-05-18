# DatabaseDriver

Test helpers and CI

- Run unit tests:

```bash
make unit
```

- Run integration tests locally (requires Docker):

```bash
make integration
# or
sh ./scripts/run_integration_tests.sh
```

Integration tests are skipped by default; the test checks `RUN_DOCKER_INTEGRATION=1`.
