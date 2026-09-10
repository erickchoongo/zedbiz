from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

_SENSITIVE_FIELDS = {"password", "refresh_token"}


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def safe_validation_error(
        request: Request,
        exc: RequestValidationError,
    ) -> JSONResponse:
        errors: list[dict[str, object]] = []
        for original in exc.errors():
            error = {key: original[key] for key in ('type', 'loc', 'msg') if key in original}
            location = {str(part) for part in error.get("loc", ())}
            if location & _SENSITIVE_FIELDS:
                error["input"] = "[redacted]"
            errors.append(error)
        return JSONResponse(status_code=422, content={"detail": jsonable_encoder(errors)})
