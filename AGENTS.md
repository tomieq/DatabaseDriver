Simple pure Swift MySQL/MariaDB driver to make working with databases easier.
Implemented as full Swift 6 structured concurrecy to work on MacOS, iOS and Linux platforms.

## Testing instructions
Local MacOS machine has docker running with images: mysql:9.7.0 and swift:6.1
- Run `swift tests` for unit test on local MacOS
- Run `sh ./scripts/run_integration_tests.sh` for integration test on local MacOS
Use docker images to run units and integration tests on linux
