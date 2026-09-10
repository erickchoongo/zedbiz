from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.concurrency import run_in_threadpool
from contextlib import asynccontextmanager
from app.core.request_policy import RequestPolicy
from app.core.readiness import check_database
from app.db.session import engine

from app.api.v1.router import api_router
from app.core.config import Settings, get_settings
from app.core.logging import configure_logging
from app.core.errors import register_error_handlers


def create_app(settings: Settings | None = None) -> FastAPI:
    application_settings = settings or get_settings()
    configure_logging(application_settings.app_env, application_settings.log_level)

    @asynccontextmanager
    async def lifespan(app):
        if application_settings.app_env in {'production', 'staging'}:
            def verify():
                try:
                    with engine.connect() as connection:
                        check_database(connection, production=True)
                except Exception:
                    raise RuntimeError('Production database readiness check failed; verify connectivity, role and migrations') from None
            await run_in_threadpool(verify)
        yield

    app = FastAPI(
        title=application_settings.app_name,
        docs_url="/docs" if application_settings.app_env != "production" else None,
        redoc_url=None,
        openapi_url='/openapi.json' if application_settings.app_env not in {'production', 'staging'} else None,
        lifespan=lifespan,
    )
    app.state.settings = application_settings
    app.add_middleware(RequestPolicy, settings=application_settings)
    if application_settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=application_settings.cors_origins,
            allow_credentials=True,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type"],
            expose_headers=['X-Request-ID', 'Retry-After'],
        )
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=application_settings.trusted_hosts)
    register_error_handlers(app)
    app.include_router(api_router, prefix="/api/v1")
    return app


app = create_app()
