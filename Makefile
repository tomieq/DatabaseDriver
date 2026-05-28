.PHONY: test unit integration integration-docker clean-docker

test: unit

unit:
	swift test -v

integration:
	./scripts/run_integration_tests.sh

integration-docker:
	./scripts/run_docker_integration_tests.sh

clean-docker:
	docker rm -f mysql_integration dbdriver-mysql dbdriver-swift-test || true
	docker network rm dbdriver-test-net || true
