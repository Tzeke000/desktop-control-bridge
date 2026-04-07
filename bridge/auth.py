from __future__ import annotations

from fastapi import HTTPException, Request, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from bridge.action_log import log_auth_rejection
from bridge.config import get_settings

_bearer = HTTPBearer(auto_error=False)


def require_token(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Security(_bearer),
) -> None:
    settings = get_settings()
    expected = (settings.bridge_token or "").strip()
    if not expected:
        log_auth_rejection("server_token_not_configured")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Bridge token is not configured. Set BRIDGE_TOKEN in .env.",
        )

    if credentials is None or credentials.scheme.lower() != "bearer":
        log_auth_rejection("missing_or_invalid_scheme", client=_client_hint(request))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing or invalid Authorization header. Use: Authorization: Bearer <token>",
        )

    token = (credentials.credentials or "").strip()
    if token != expected:
        log_auth_rejection("token_mismatch", client=_client_hint(request))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )


def _client_hint(request: Request) -> str:
    try:
        return request.client.host if request.client else ""
    except Exception:
        return ""
