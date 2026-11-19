import json
import logging
import os
import sys
from datetime import datetime, timezone
from fastapi import FastAPI, Request, Response, status

APP_VERSION = os.getenv("APP_VERSION", "dev")
GIT_SHA = os.getenv("GIT_SHA", "unknown")
BUILD_TIME = os.getenv("BUILD_TIME", "unknown")
FAIL_READINESS = os.getenv("FAIL_READINESS", "false").lower() == "true"


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        log_record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "release_version": APP_VERSION,
            "git_sha": GIT_SHA,
            "message": record.getMessage(),
        }
        return json.dumps(log_record)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logger = logging.getLogger("delivery-service")
logger.setLevel(logging.INFO)
logger.addHandler(handler)
logger.propagate = False

app = FastAPI(title="Delivery Demo Service", version=APP_VERSION)


@app.on_event("startup")
def on_startup() -> None:
    logger.info(f"Service starting (fail_readiness={FAIL_READINESS})")


@app.middleware("http")
async def log_requests(request: Request, call_next):
    response = await call_next(request)
    logger.info(f"{request.method} {request.url.path} -> {response.status_code}")
    return response


@app.get("/health/live")
def health_live():
    return {"status": "alive", "version": APP_VERSION}


@app.get("/health/ready")
def health_ready(response: Response):
    if FAIL_READINESS:
        logger.warning("Readiness check failed: FAIL_READINESS=true")
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {
            "status": "not_ready",
            "reason": "configured_to_fail_readiness",
            "version": APP_VERSION,
        }
    return {"status": "ready", "version": APP_VERSION}


@app.get("/version")
def version():
    return {
        "version": APP_VERSION,
        "git_sha": GIT_SHA,
        "build_time": BUILD_TIME,
    }


@app.get("/work")
def work():
    return {
        "status": "ok",
        "result": "work_completed",
        "version": APP_VERSION,
    }
