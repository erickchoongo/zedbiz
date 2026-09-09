from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import Settings, get_settings
from app.core.logging import configure_logging
from app.core.errors import register_error_handlers


def create_app(settings: Settings | None = None) -> FastAPI:
    application_settings = settings or get_settings()
    configure_logging(application_settings.app_env)

    app = FastAPI(
        title=application_settings.app_name,
        docs_url="/docs" if application_settings.app_env != "production" else None,
        redoc_url=None,
    )
    if application_settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=application_settings.cors_origins,
            allow_credentials=True,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type"],
        )
    register_error_handlers(app)
    app.include_router(api_router, prefix="/api/v1")
    return app


app = create_app()
