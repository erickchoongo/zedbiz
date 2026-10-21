"""Run this checkout against the isolated suspension database, never hosted data.

From backend: .venv/Scripts/python.exe ops/start_suspension_local.py
Uses port 18001 to avoid existing Docker APIs on 8000/8001.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

import psycopg
from sqlalchemy.engine import URL


def main():
    container = json.loads(subprocess.check_output(
        ["docker", "inspect", "zedbiz-suspension-test-db"],
    ))[0]
    values = dict(value.split("=", 1) for value in container["Config"]["Env"]
                  if "=" in value)
    if (values.get("POSTGRES_DB") != "zedbiz_suspension_test"
            or container["HostConfig"]["PortBindings"].get("5432/tcp") != [
                {"HostIp": "127.0.0.1", "HostPort": "55432"}]):
        raise SystemExit("Refusing unexpected local database destination")
    connection = dict(host="127.0.0.1", port=55432,
                      dbname="zedbiz_suspension_test",
                      user=values["POSTGRES_USER"],
                      password=values["POSTGRES_PASSWORD"], connect_timeout=5)
    with psycopg.connect(**connection, options="-c default_transaction_read_only=on") as db:
        if db.execute("SELECT current_database()").fetchone()[0] != connection["dbname"]:
            raise SystemExit("Unexpected database")
        if db.execute("SELECT version_num FROM alembic_version").fetchall() != [
            ("20261019_0008",)
        ]:
            raise SystemExit("Suspension migration is not present; no migrations executed")
    env = os.environ.copy()
    env.update(
        APP_ENV="development", REQUIRE_PRODUCTION="false",
        DATABASE_SSL_REQUIRED="false", TRUSTED_HOSTS="127.0.0.1,localhost,test",
        DATABASE_URL=URL.create(
            "postgresql+psycopg", username=connection["user"],
            password=connection["password"], host=connection["host"],
            port=connection["port"], database=connection["dbname"],
        ).render_as_string(hide_password=False),
    )
    root = Path(__file__).resolve().parents[1]
    print("Verified isolated database; serving this checkout at http://127.0.0.1:18001", flush=True)
    return subprocess.call(
        [sys.executable, "-m", "uvicorn", "app.main:app",
         "--app-dir", str(root), "--host", "127.0.0.1", "--port", "18001"],
        cwd=root, env=env,
    )


if __name__ == "__main__":
    raise SystemExit(main())
