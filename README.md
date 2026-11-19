# Delivery Workflow — AI-First Delivery Engineer Take-Home

A repeatable, locally runnable delivery workflow for a minimal Python (FastAPI) HTTP service. It demonstrates immutable release packaging, automated verification, bad-release detection, automatic rollback with honest failure reporting, and operational runbooks without introducing unnecessary platform complexity.

---

## Prerequisites

- **Docker** & **Docker Compose** (v2+)
- **Bash**, **curl**, **make**, and **git**
- Port `8000` available locally (override with `APP_PORT=<port>`)

*(macOS Docker Desktop note: ensure `/Applications/Docker.app/Contents/Resources/bin` is in your `$PATH` so `docker-credential-desktop` is found.)*

---

## Quick Start (Under 10 Minutes)

Make scripts executable and run the end-to-end demonstration (Deploy `1.0.0` → Attempt failing `2.0.0` → Detect failure & auto-rollback → Verify `1.0.0` restored):

```bash
chmod +x scripts/*.sh
make demo
```

### Individual Commands

| Action | Command |
| :--- | :--- |
| Build a specific version | `make build VERSION=1.0.0` |
| Deploy and verify | `make deploy VERSION=1.0.0` |
| Reproduce a bad release | `make deploy VERSION=2.0.0 FAIL_READINESS=true` |
| Verify running service | `make verify VERSION=1.0.0` |
| Manual rollback to last known good | `make rollback` |
| Inspect current state & logs | `make status` |
| Stop and remove container | `make down` |

---

## Key Decisions, Downtime & Limitations

- **Immutable Release Identification:** Images are tagged explicitly (`delivery-demo:<version>`), never relying on `latest`. `APP_VERSION`, `GIT_SHA`, and `BUILD_TIME` are injected at build time as OCI labels and environment variables, exposed via `GET /version`, and included in every JSON log line. No secrets are embedded in the image or repo.
- **Automatic Rollback + Non-Zero Exit Code:** `scripts/deploy.sh` stores the last verified release and its runtime config in `.deploy-state/last_known_good.env`. If a new release fails readiness, version, or functional checks within the bounded timeout (`VERIFY_TIMEOUT`), `deploy.sh` automatically invokes `scripts/rollback.sh` to restore the previous version and **still exits with status `1`** so CI pipelines and operators know the deployment failed. `scripts/rollback.sh` can also be invoked manually at any time.
- **Expected Downtime:** Because this local setup uses a single container with `docker compose up -d --force-recreate`, there is a brief **~2–5 second interruption** during container replacement and rollback.
- **Known Limitations:** State is persisted locally in `.deploy-state/` (not suitable for multi-host or concurrent deploys), there is no container registry push, and no TLS termination locally.

---

## Operational Runbook

### 1. Deploy, Verify, and Recover
- **Deploy:** `make build VERSION=<ver> && make deploy VERSION=<ver>`
- **Verify:** `make verify VERSION=<ver>` checks `/health/ready` (HTTP 200 within timeout), `/version` match, and `/work` (HTTP 200).
- **Recover:** Rollback triggers automatically on failed deploys. For manual recovery to the last known good release, run `make rollback`.

### 2. Determine Which Version Is Running
Run `make status` or query the live endpoint directly:
```bash
curl -s http://localhost:8000/version
```
This returns `version`, `git_sha`, and `build_time`. To inspect the OCI metadata on the container image:
```bash
docker inspect --format '{{json .Config.Labels}}' delivery-demo-app
```

### 3. Diagnostic Output
- **Quick snapshot (container, last known good state, health endpoints, last 10 logs):** `make status`
- **Live structured JSON logs (tagged with `release_version` and `git_sha`):**
  ```bash
  docker logs -f delivery-demo-app
  ```

### 4. Production Alert Signals

| Alert Signal | Why It Matters | First Engineer Action |
| :--- | :--- | :--- |
| **5xx Error Rate > 1% for 5m** | Indicates broken release, unhandled exceptions, or backend dependency failure impacting users. | Check `/version` and recent deploy timeline; inspect JSON logs filtered by `release_version`; roll back if correlated with a recent release. |
| **Readiness Check Failure / Unhealthy Target Count > 0** | Instances are being pulled from the load balancer; risks capacity loss or total outage if all tasks fail. | Inspect container logs for startup/readiness errors and check recent config/secret changes; halt any in-progress rollout. |
| **p95 Latency Spike (> 2x baseline) or AI-Provider 429/5xx Rate** | Slow external AI calls or DB contention can exhaust worker threads and cascade into timeouts across the API. | Check downstream dependency dashboards (AI provider & RDS); verify circuit breaker/rate-limit metrics; shed non-critical AI traffic if needed. |

---

## Production Design Note (AWS)

*(Proposed architecture — not implemented in this local repository.)*

### Architecture Overview

| Layer | Proposed Choice (AWS) | Rationale |
| :--- | :--- | :--- |
| **Compute & Networking** | **ECS Fargate** behind an **Application Load Balancer (ALB)** in private subnets (public ALB, private tasks). | Zero server/cluster patching overhead for a small team; native ALB health checks and rolling/blue-green deploys. |
| **Release Approach** | Immutable images pushed to **ECR** tagged with `<semver>-<git-sha>`. Rolling or Blue/Green deploys via ECS/CodeDeploy with ALB `/health/ready` checks and automatic circuit-breaker rollback. | Eliminates laptop deploys and enforces zero-downtime cutovers with automated rollback. |
| **IaC & Environments** | **Terraform** with reusable modules and isolated state per environment (`dev`, `staging`, `prod` in separate AWS accounts or strict VPC isolation). | Prevents blast radius across environments and makes infrastructure changes reviewable via PRs. |
| **Identity & Secrets** | **IAM Task Execution Role** (ECR pull, logs) + **IAM Task Role** (least-privilege app access). Secrets in **AWS Secrets Manager** injected at runtime. | No static AWS keys, no secrets in Git or Docker images, easy rotation. |
| **Database & Backups** | **Amazon RDS (PostgreSQL)** Multi-AZ with automated daily snapshots + Point-in-Time Recovery (PITR). | Automated failover and recovery. **Recovery verification:** scheduled monthly/quarterly automated restore drill into an ephemeral RDS instance running a smoke query to validate backup integrity and RTO. |
| **Observability & Cost Drivers** | Structured JSON logs to **CloudWatch Logs** (with retention caps, e.g., 30 days), ALB/ECS/RDS metrics + alarms. | **Main cost drivers:** external AI-provider token usage, NAT Gateway data processing (mitigate with VPC Endpoints for ECR/Secrets Manager/CloudWatch), CloudWatch log ingestion volume, and RDS/Fargate right-sizing. |

### Operational Scenarios

1. **Database Schema Changes & Rollback:**
   Use the **Expand-and-Contract** pattern across separate releases:
   - *Expand:* Add new nullable columns/tables (backward-compatible) and deploy.
   - *Migrate:* Deploy app version that writes/reads compatibly, then backfill data.
   - *Contract:* Once the new version is stable and rollback is no longer needed, drop old columns in a subsequent release.
   - **App Rollback vs. DB Restore:** An *application rollback* simply reverts stateless containers to the previous image (takes seconds, zero data loss) and works safely because the schema remained backward-compatible. *Restoring a DB backup* is a last-resort disaster recovery operation (takes minutes/hours and incurs RPO data loss for writes after the restore point).

2. **AI-Provider Degradation (Latency / Rate Limits):**
   - Enforce strict **connect/read timeouts** (e.g., 2s connect, 15s read) so worker pools do not stall.
   - Use **bounded retries** (max 2–3 attempts) with **exponential backoff + jitter**, honoring `Retry-After` headers and retrying only transient errors (`429`, `502`, `503`, `504`).
   - Protect the service with a **circuit breaker** (fail fast when error rate exceeds threshold) and **per-tenant/global rate limits + daily spend caps** to bound cost.
   - Isolate AI calls (dedicated worker pool/async queue) and return graceful degraded responses so core non-AI API endpoints remain healthy.

3. **Dependency Health — Liveness vs. Readiness:**
   - **Liveness (`/health/live`):** Must check **only the application process itself**—never the DB or AI provider. Checking external dependencies in liveness causes cascading container restart loops during an external outage.
   - **Readiness (`/health/ready`):** Must **not** fail on AI-provider degradation; the service should stay in rotation and degrade AI features gracefully. For the relational DB, failing readiness for a global DB outage removes *all* healthy containers from the ALB and causes total downtime (even for cached/non-DB routes) plus thundering-herd reconnects on recovery. Prefer returning HTTP `503` on DB-dependent endpoints, keeping readiness focused on local startup/config/pool initialization, and alerting immediately on DB error rates.

---

## AI-Agent Usage Notes

- **Tool Used & Delegation:** Used **Gemini** to scaffold the FastAPI service, `Dockerfile`, `docker-compose.yml`, Bash automation scripts (`build.sh`, `deploy.sh`, `verify.sh`, `rollback.sh`, `status.sh`), `Makefile`, GitHub Actions workflow, and initial documentation structure.
- **Concrete Prompt & Output:** Provided the assignment specification and asked for a minimal Python service + local Docker Compose workflow with bounded readiness verification and automatic rollback returning a non-zero exit code. The agent produced the modular script structure and `Makefile` demo target.
- **Changes & Fixes Applied:**
  - During local execution of `make demo`, `scripts/status.sh` failed at step 4 because `docker compose ps` required `APP_VERSION` interpolation defined in `docker-compose.yml`. Replaced it with `docker ps --filter "name=delivery-demo-app"` and updated `Makefile` (`down`) and CI cleanup to pass `APP_VERSION` explicitly.
  - Resolved a macOS Docker Desktop credential helper path issue (`docker-credential-desktop` not in `$PATH`) during local validation.
- **Independent Validation:** Executed `make demo` locally end-to-end, verified container state, HTTP responses (`/version`, `/health/live`, `/health/ready`, `/work`), JSON log fields, non-zero exit code on bad release `2.0.0`, automatic rollback to `1.0.0`, and verified the GitHub Actions CI run.
- **Limitation / Risk Checked:** Specifically verified that (1) `deploy.sh` still exits non-zero even after a successful automatic rollback (so CI does not report a false green), (2) the container runs as a non-root user without embedded secrets, and (3) image tags do not fall back to `latest`.

---

## Verification Evidence & Written Walkthrough

### Walkthrough Summary
1. **Packaging (`scripts/build.sh`):** Builds `delivery-demo:<version>` with `APP_VERSION`, `GIT_SHA`, and `BUILD_TIME` baked into OCI labels and env vars.
2. **Release A (`1.0.0`):** `deploy.sh` starts the container, `verify.sh` confirms `/health/ready` (200), `/version` (`1.0.0`), and `/work` (200), then records `1.0.0` in `.deploy-state/last_known_good.env`.
3. **Bad Release B (`2.0.0`):** Deployed with `FAIL_READINESS=true`. The container starts (liveness is 200), proving "container started" ≠ "release succeeded". `verify.sh` times out on HTTP 503, prints container logs, triggers `rollback.sh` to restore `1.0.0`, verifies `1.0.0` is healthy, and exits with code `1`.
4. **CI Parity (`.github/workflows/ci.yml`):** Runs Python/Bash syntax checks and executes the exact same build, deploy, bad-release detection, and rollback verification on a disposable GitHub Actions runner.

### Captured Output (`make demo`)

```text
$ make demo
>>> 1. Build y deploy de versión A (1.0.0)...
./scripts/build.sh 1.0.0
[build] Construyendo delivery-demo:1.0.0 (git_sha=6453a28, build_time=2026-11-19T22:00:55Z)...
[build] Imagen lista: delivery-demo:1.0.0
FAIL_READINESS=false ./scripts/deploy.sh 1.0.0
[deploy] Iniciando despliegue: version=1.0.0, FAIL_READINESS=false
[+] up 1/1
 ✔ Container delivery-demo-app Started                                      0.5s
[verify] Esperando readiness en http://localhost:8000/health/ready (timeout=10s)...
[verify] OK: /health/ready respondió HTTP 200 en 1s.
[verify] OK: /version confirmado ({"version":"1.0.0","git_sha":"6453a28","build_time":"2026-11-19T22:00:55Z"}).
[verify] OK: /work respondió HTTP 200 ({"status":"ok","result":"work_completed","version":"1.0.0"}).
[deploy] ÉXITO: Release 1.0.0 desplegado y guardado como last_known_good.

>>> 2. Build e intento de deploy de versión B (2.0.0) con readiness fallando...
./scripts/build.sh 2.0.0
[build] Construyendo delivery-demo:2.0.0 (git_sha=6453a28, build_time=2026-11-19T22:01:03Z)...
[build] Imagen lista: delivery-demo:2.0.0
[deploy] Iniciando despliegue: version=2.0.0, FAIL_READINESS=true
[+] up 1/1
 ✔ Container delivery-demo-app Started                                      0.4s
[verify] Esperando readiness en http://localhost:8000/health/ready (timeout=5s)...
[verify] ERROR: Timeout (5s) esperando readiness. Último HTTP=503.
[verify] Respuesta: {"status":"not_ready","reason":"configured_to_fail_readiness","version":"2.0.0"}
[deploy] FALLO: El release 2.0.0 no superó la verificación.
[deploy] Últimos logs del contenedor fallido:
INFO:     Started server process [1]
INFO:     Waiting for application startup.
{"timestamp": "2026-11-19T22:01:09.442841+00:00", "level": "INFO", "release_version": "2.0.0", "git_sha": "6453a28", "message": "Service starting (fail_readiness=True)"}
INFO:     Application startup complete.
INFO:     Uvicorn running on [http://0.0.0.0:8000](http://0.0.0.0:8000) (Press CTRL+C to quit)
{"timestamp": "2026-11-19T22:01:10.151197+00:00", "level": "WARNING", "release_version": "2.0.0", "git_sha": "6453a28", "message": "Readiness check failed: FAIL_READINESS=true"}
{"timestamp": "2026-11-19T22:01:10.151583+00:00", "level": "INFO", "release_version": "2.0.0", "git_sha": "6453a28", "message": "GET /health/ready -> 503"}
[deploy] Iniciando rollback automático al último release sano...
[rollback] Restaurando último release sano: version=1.0.0 (FAIL_READINESS=false)...
[+] up 1/1
 ✔ Container delivery-demo-app Started                                      0.4s
[verify] Esperando readiness en http://localhost:8000/health/ready (timeout=15s)...
[verify] OK: /health/ready respondió HTTP 200 en 1s.
[verify] OK: /version confirmado ({"version":"1.0.0","git_sha":"6453a28","build_time":"2026-11-19T22:00:55Z"}).
[verify] OK: /work respondió HTTP 200 ({"status":"ok","result":"work_completed","version":"1.0.0"}).
[rollback] OK: Release 1.0.0 restaurado y verificado.
[deploy] Rollback completado, pero el despliegue de 2.0.0 se reporta como FALLIDO (exit 1).
>>> 3. Fallo detectado correctamente (exit code=1) y rollback ejecutado.

>>> 4. Verificando estado final restaurado (1.0.0)...
./scripts/status.sh
=== Estado del contenedor ===
NAMES               IMAGE                 STATUS        PORTS
delivery-demo-app   delivery-demo:1.0.0   Up 1 second   0.0.0.0:8000->8000/tcp, [::]:8000->8000/tcp

=== Último release sano registrado ===
APP_VERSION=1.0.0
FAIL_READINESS=false
APP_PORT=8000
DEPLOYED_AT=2026-11-19T22:01:03Z

=== Endpoints en vivo ===
GET /version:      {"version":"1.0.0","git_sha":"6453a28","build_time":"2026-11-19T22:00:55Z"}
GET /health/live:  {"status":"alive","version":"1.0.0"}
GET /health/ready: {"status":"ready","version":"1.0.0"}

=== Últimos 10 logs ===
{"timestamp": "2026-11-19T22:01:15.454619+00:00", "level": "INFO", "release_version": "1.0.0", "git_sha": "6453a28", "message": "Service starting (fail_readiness=False)"}
{"timestamp": "2026-11-19T22:01:16.157466+00:00", "level": "INFO", "release_version": "1.0.0", "git_sha": "6453a28", "message": "GET /health/ready -> 200"}
{"timestamp": "2026-11-19T22:01:16.185641+00:00", "level": "INFO", "release_version": "1.0.0", "git_sha": "6453a28", "message": "GET /version -> 200"}
{"timestamp": "2026-11-19T22:01:16.210833+00:00", "level": "INFO", "release_version": "1.0.0", "git_sha": "6453a28", "message": "GET /work -> 200"}
{"timestamp": "2026-11-19T22:01:16.274744+00:00", "level": "INFO", "release_version": "1.0.0", "git_sha": "6453a28", "message": "GET /version -> 200"}
{"timestamp": "2026-11-19T22:01:16.292726+00:00", "level": "INFO", "release_version": "1.0.0", "git_sha": "6453a28", "message": "GET /health/live -> 200"}
{"timestamp": "2026-11-19T22:01:16.310713+00:00", "level": "INFO", "release_version": "1.0.0", "git_sha": "6453a28", "message": "GET /health/ready -> 200"}
```

## Time Spent & Prioritized Next Steps

- **Approximate Time Spent:** ~2.5 hours (implementation, local troubleshooting/validation, CI setup, and documentation).
- **Prioritized Next Steps (if extending beyond the time limit):**
  1. Add unit/integration tests with `pytest` for endpoint contracts and readiness failure behavior.
  2. Support zero-downtime local/CI cutovers (e.g., side-by-side container swap behind a lightweight reverse proxy like Caddy/Nginx).
  3. Add image vulnerability scanning (e.g., Trivy) and `shellcheck` linting to the GitHub Actions workflow.
  4. Implement the AWS ECS Fargate + RDS setup in Terraform following the Production Design Note.
