from __future__ import annotations

import logging
import os
from typing import Any

PIPELINE_LOGGER_NAME = "hydralis.pipeline"
REQUEST_LOGGER_NAME = "hydralis.request"

_LOG_FORMAT = "%(asctime)s %(levelname)-5s [%(name)s] %(message)s"
_DATE_FORMAT = "%Y-%m-%d %H:%M:%S"


def configure_logging() -> None:
    level = os.getenv("LOG_LEVEL", "INFO").upper()
    root = logging.getLogger()
    if not any(getattr(handler, "_hydralis", False) for handler in root.handlers):
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter(_LOG_FORMAT, datefmt=_DATE_FORMAT))
        handler._hydralis = True  # type: ignore[attr-defined]
        root.addHandler(handler)
    root.setLevel(level)

    for name in ("uvicorn", "uvicorn.error", "uvicorn.access", PIPELINE_LOGGER_NAME, REQUEST_LOGGER_NAME):
        logging.getLogger(name).setLevel(level)


def get_pipeline_logger(pipeline: str) -> logging.LoggerAdapter:
    return logging.LoggerAdapter(
        logging.getLogger(f"{PIPELINE_LOGGER_NAME}.{pipeline}"),
        {"pipeline": pipeline},
    )


def log_step(logger: logging.LoggerAdapter | logging.Logger, step: str, **fields: Any) -> None:
    if fields:
        parts = " ".join(f"{key}={_format_value(value)}" for key, value in fields.items())
        logger.info("step=%s %s", step, parts)
    else:
        logger.info("step=%s", step)


def _format_value(value: Any) -> str:
    if isinstance(value, float):
        return f"{value:.4g}"
    text = str(value)
    if len(text) > 200:
        return f"{text[:200]}…"
    return text
