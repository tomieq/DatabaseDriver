Simple pure Swift MySQL/MariaDB driver to make working with databases easier.
Implemented as full Swift 6 structured concurrecy to work on MacOS, iOS and Linux platforms.

## Project Structure
All new classes/structs/enums put in appropriate folder in separate file. Do not create long files with multiple definitions inside. Although you can add type's extensions in the same file as extended type. If you need extend some object to protocol, name file ObjectType+ProtocolName.swift.

## Building project
- Run `swift build` to build the project on local MacOS
- Run `docker run --rm -t  -v "$PWD":/workspace -w /workspace swift:6.1  swift build` to build the project in linux Swift 6.1
Remember to clean build folder (`rm -rf .build`) when building for different platform.

## Testing
Local MacOS machine has docker running with images: mysql:9.7.0 and swift:6.1
- Run `swift test` for unit test on local MacOS
- Run `make integration` for integration test on local MacOS; the test will start its own MySQL container on `127.0.0.1:3307`
- Run `docker run --rm -t  -v "$PWD":/workspace -w /workspace swift:6.1 swift test --jobs 1` for unit test on linux
- Run `make integration-docker SWIFT_DOCKER_IMAGE=swift:6.1` for integration test on linux; It will launch myqsl docker container in the same docker network as tests

## Change commit
Never commit anything, let user review changes.
