from typing import Annotated

from fastapi import Depends, HTTPException, status

from app.api.dependencies.auth import CurrentUser
from app.models.user import User


def require_platform_admin(current_user: CurrentUser) -> User:
    if not current_user.is_platform_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Platform administrator access required")
    return current_user


PlatformAdmin = Annotated[User, Depends(require_platform_admin)]
