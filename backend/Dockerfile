FROM python:3.12.14-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.12.6 /uv /uvx /bin/
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project

FROM python:3.12.14-slim AS runtime
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
RUN groupadd --system zedbiz && useradd --system --gid zedbiz --home-dir /app zedbiz
WORKDIR /app
COPY --from=builder --chown=zedbiz:zedbiz /app/.venv /app/.venv
COPY --chown=zedbiz:zedbiz alembic.ini ./
COPY --chown=zedbiz:zedbiz migrations ./migrations
COPY --chown=zedbiz:zedbiz app ./app
COPY --chown=zedbiz:zedbiz ops ./ops
USER zedbiz
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=8s --start-period=15s --retries=3 CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health/ready', timeout=5)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log", "--no-proxy-headers"]
