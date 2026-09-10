import json
import logging
from logging.config import dictConfig


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, object] = {
            "timestamp": self.formatTime(record),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        payload['environment'] = getattr(self, 'environment', 'unknown')
        for key in ('request_id', 'method', 'path', 'status', 'duration_ms', 'error_type'):
            if hasattr(record, key):
                payload[key] = getattr(record, key)
        # Never serialize exception text: database exceptions can contain parameters.
        return json.dumps(payload, ensure_ascii=False)


def configure_logging(environment: str, level: str = 'INFO') -> None:
    dictConfig(
        {
            "version": 1,
            "disable_existing_loggers": False,
            "formatters": {
                "structured": {
                    "()": "app.core.logging.JsonFormatter",
                }
            },
            "handlers": {
                "console": {
                    "class": "logging.StreamHandler",
                    "formatter": "structured",
                }
            },
            "root": {
                "handlers": ["console"],
                "level": level,
            },
        }
    )
    logging.captureWarnings(True)
    for handler in logging.getLogger().handlers:
        handler.formatter.environment = environment
    logging.getLogger('sqlalchemy.engine').setLevel(logging.WARNING)
    logging.getLogger('httpx').setLevel(logging.WARNING)
