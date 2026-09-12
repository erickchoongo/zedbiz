"""Render's single-process entrypoint. Never migrates or seeds on startup."""
import os
import sys


def command():
    port = os.environ.get('PORT', '')
    if not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise RuntimeError('PORT must be supplied by Render as a valid TCP port')
    os.environ.setdefault('APP_ENV', 'production')
    os.environ['REQUIRE_PRODUCTION'] = 'true'
    os.environ['DATABASE_SSL_REQUIRED'] = 'true'
    os.environ.setdefault('GIT_COMMIT', os.environ.get('RENDER_GIT_COMMIT', 'unknown'))
    return [sys.executable, '-m', 'uvicorn', 'app.main:app', '--host', '0.0.0.0',
            '--port', str(int(port)), '--workers', '1', '--no-access-log', '--no-proxy-headers']


if __name__ == '__main__':
    os.execv(sys.executable, command())
