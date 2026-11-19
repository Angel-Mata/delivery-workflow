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
	APP_VERSION=$(VERSION) docker compose down

demo:
	@echo ">>> 1. Build y deploy de versión A (1.0.0)..."
	./scripts/build.sh 1.0.0
	FAIL_READINESS=false ./scripts/deploy.sh 1.0.0
	@echo ""
	@echo ">>> 2. Build e intento de deploy de versión B (2.0.0) con readiness fallando..."
	./scripts/build.sh 2.0.0
	@if FAIL_READINESS=true VERIFY_TIMEOUT=5 ./scripts/deploy.sh 2.0.0; then \
		echo "ERROR: El despliegue de 2.0.0 debió fallar."; exit 1; \
	else \
		EXIT_CODE=$$?; \
		echo ">>> 3. Fallo detectado correctamente (exit code=$$EXIT_CODE) y rollback ejecutado."; \
	fi
	@echo ""
	@echo ">>> 4. Verificando estado final restaurado (1.0.0)..."
	./scripts/status.sh
