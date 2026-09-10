"""Bounded process-local pilot limits, sanitized request logs and safe failures.

One process/replica only. Replace WindowLimiter with a shared atomic store before
scaling; neither caller-controlled forwarding headers nor raw identities are keys.
"""
import hashlib
import hmac
import json
import logging
import math
import time
import uuid

from starlette.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError

log = logging.getLogger('zedbiz.requests')


class WindowLimiter:
    def __init__(self, window, capacity=10000, clock=time.monotonic):
        self.window, self.capacity, self.clock = window, capacity, clock
        self.entries = {}

    def allow(self, key, limit):
        now = self.clock()
        if len(self.entries) >= self.capacity:
            self.entries = {k: v for k, v in self.entries.items() if v[1] > now}
        count, end = self.entries.get(key, (0, now+self.window))
        if end <= now:
            count, end = 0, now+self.window
        if key not in self.entries and len(self.entries) >= self.capacity:
            return False, self.window
        if count >= limit:
            return False, max(1, math.ceil(end-now))
        self.entries[key] = (count+1, end)
        return True, 0


class RequestPolicy:
    def __init__(self, app, settings):
        self.app, self.settings = app, settings
        self.limiter = WindowLimiter(settings.rate_limit_window_seconds)

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http':
            return await self.app(scope, receive, send)
        started = time.monotonic()
        request_id = uuid.uuid4().hex
        scope.setdefault('state', {})['request_id'] = request_id
        status = 500
        response_started = False

        async def safe_send(message):
            nonlocal status, response_started
            if message['type'] == 'http.response.start':
                response_started = True
                status = message['status']
                message['headers'] = list(message.get('headers', [])) + [
                    (b'x-request-id', request_id.encode()),
                    (b'x-content-type-options', b'nosniff'),
                    (b'x-frame-options', b'DENY'),
                    (b'referrer-policy', b'no-referrer'),
                    (b'cache-control', b'no-store'),
                ]
            await send(message)

        async def reject(code, detail, headers=None):
            await JSONResponse({'detail': detail, 'request_id': request_id}, status_code=code, headers=headers)(scope, receive, safe_send)

        try:
            path = scope['path']
            health = path in {'/api/v1/health', '/api/v1/health/ready'}
            enabled = self.settings.rate_limit_enabled and self.settings.app_env != 'test'
            peer = (scope.get('client') or ('unknown', 0))[0]
            if enabled and not health:
                limits = [('api:'+peer, self.settings.rate_limit_api)]
                for endpoint in ('login', 'register', 'refresh'):
                    if path == '/api/v1/auth/'+endpoint:
                        limits.append((endpoint+':'+peer, getattr(self.settings, 'rate_limit_'+endpoint)))
                for key, limit in limits:
                    allowed, retry = self.limiter.allow(key, limit)
                    if not allowed:
                        return await reject(429, 'Too many requests. Please try again shortly.', {'Retry-After': str(retry)})
            chunks, size = [], 0
            while True:
                message = await receive()
                if message['type'] == 'http.disconnect':
                    return
                size += len(message.get('body', b''))
                if size > self.settings.max_request_bytes:
                    return await reject(413, 'Request is too large.')
                chunks.append(message.get('body', b''))
                if not message.get('more_body', False):
                    break
            body = b''.join(chunks)
            if enabled and path == '/api/v1/auth/login':
                try:
                    payload = json.loads(body)
                    email = payload.get('email', '') if isinstance(payload, dict) else ''
                    if isinstance(email, str):
                        digest = hmac.new(self.settings.jwt_secret.encode(), email.strip().lower().encode(), hashlib.sha256).hexdigest()
                        allowed, retry = self.limiter.allow('account:'+digest, self.settings.rate_limit_account)
                        if not allowed:
                            return await reject(429, 'Too many requests. Please try again shortly.', {'Retry-After': str(retry)})
                except (ValueError, UnicodeError):
                    pass
            delivered = False

            async def replay():
                nonlocal delivered
                if not delivered:
                    delivered = True
                    return {'type': 'http.request', 'body': body, 'more_body': False}
                return await receive()

            await self.app(scope, replay, safe_send)
        except Exception as exc:
            # Exception strings/tracebacks may contain SQL parameters and secrets.
            log.error('request_failed', extra={'request_id': request_id, 'error_type': type(exc).__name__})
            if not response_started:
                await reject(503 if isinstance(exc, SQLAlchemyError) else 500,
                             'Service temporarily unavailable.' if isinstance(exc, SQLAlchemyError) else 'An unexpected error occurred. Contact support with the request ID.')
        finally:
            route = scope.get('route')
            route_path = scope['path'] if route is not None else '<unmatched>'
            for name, value in scope.get('path_params', {}).items():
                route_path = route_path.replace('/'+str(value), '/{'+name+'}')
            event = 'authentication_request' if route_path.startswith('/api/v1/auth/') else 'http_request'
            log.info(event, extra={'request_id': request_id, 'method': scope['method'], 'path': route_path,
                                  'status': status, 'duration_ms': round((time.monotonic()-started)*1000, 2)})
