.PHONY: build deploy verify rollback status down demo

VERSION ?= 1.0.0
FAIL_READINESS ?= false

build:
	./scripts/build.sh $(VERSION)

deploy:
	FAIL_READINESS=$(FAIL_READINESS) ./scripts/deploy.sh $(VERSION)

verify:
	./scripts/verify.sh $(VERSION)

rollback:
	./scripts/rollback.sh

status:
	./scripts/status.sh

down:
	APP_IMAGE=delivery-demo:unused docker compose down

demo:
	@echo ">>> 1. Build and deploy release A (1.0.0)..."
	./scripts/build.sh 1.0.0
	FAIL_READINESS=false ./scripts/deploy.sh 1.0.0
	@echo ""
	@echo ">>> 2. Build and attempt deploy of release B (2.0.0) with failing readiness..."
	./scripts/build.sh 2.0.0
	@if FAIL_READINESS=true VERIFY_TIMEOUT=5 ./scripts/deploy.sh 2.0.0; then \
		echo "ERROR: Deployment of 2.0.0 should have failed."; exit 1; \
	else \
		EXIT_CODE=$$?; \
		echo ">>> 3. Failure detected as expected (exit code=$$EXIT_CODE) and rollback completed."; \
	fi
	@echo ""
	@echo ">>> 4. Verifying final restored state (1.0.0)..."
	./scripts/status.sh
	