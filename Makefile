.PHONY: test unit integration clean-docker

test: unit

unit:
	swift test -v

integration:
	sh ./scripts/run_integration_tests.sh

clean-docker:
	docker rm -f mysql_integration || true
