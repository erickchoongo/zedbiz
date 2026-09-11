"""Small read-only pilot monitor. No raw request data or environment values leave it."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import urlopen


def summarize_logs(lines):
    result = dict(http_5xx=0, database_errors=0, write_conflicts=0, write_rejections=0)
    for line in lines:
        try:
            item = json.loads(line[line.index('{'):])
        except (ValueError, TypeError):
            continue
        if not isinstance(item, dict):
            continue
        status = item.get('status', 0)
        if isinstance(status, int) and status >= 500:
            result['http_5xx'] += 1
        if item.get('error_type') in {'OperationalError', 'InterfaceError', 'DBAPIError'}:
            result['database_errors'] += 1
        path = item.get('path', '')
        if item.get('method') == 'POST' and any(p in path for p in ('/sales', '/expenses')):
            if status == 409:
                result['write_conflicts'] += 1
            if status in {402, 403, 422}:
                result['write_rejections'] += 1
    return result


def backup_health(directory, now):
    try:
        latest = json.loads((directory/'latest-backup.json').read_text(encoding='utf-8-sig'))
        attempt = json.loads((directory/'last-backup-attempt.json').read_text(encoding='utf-8-sig'))
        name = latest['file']
        if Path(name).name != name or not name.endswith('.dump'):
            raise ValueError('Invalid archive name')
        archive = directory/name
        if archive.is_symlink() or archive.resolve().parent != directory.resolve():
            raise ValueError('Invalid archive location')
        with archive.open('rb') as handle:
            digest = hashlib.file_digest(handle, 'sha256').hexdigest()
        age = (now-datetime.fromisoformat(latest['time'])).total_seconds()/3600
        valid = digest.lower() == latest['sha256'].lower()
        return {'healthy': valid and 0 <= age <= 25 and attempt['status'] == 'success',
                'age_hours': round(age, 2), 'checksum_valid': valid,
                'last_attempt': attempt['status'], 'file': name}
    except (OSError, ValueError, KeyError, TypeError):
        return {'healthy': False, 'reason': 'Missing, invalid or unreadable backup evidence'}


def probe(url):
    try:
        with urlopen(url, timeout=8) as response:
            return response.status, json.load(response)
    except HTTPError as error:
        return error.code, {}
    except (OSError, ValueError):
        return 0, {}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--api-url', required=True)
    parser.add_argument('--env-file', type=Path, required=True)
    parser.add_argument('--compose-file', type=Path, default=Path(__file__).resolve().parents[1]/'docker-compose.prod.yml')
    parser.add_argument('--backup-directory', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--local-rehearsal', action='store_true')
    args = parser.parse_args()
    url = urlsplit(args.api_url)
    if url.username or url.password or url.query or url.fragment or url.path not in ('', '/'):
        parser.error('Use a plain API origin without credentials')
    if url.scheme != 'https' and not (args.local_rehearsal and url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost')):
        parser.error('HTTPS required; explicit local rehearsal permits loopback HTTP only')
    now = datetime.now(timezone.utc)
    live, _ = probe(args.api_url.rstrip('/')+'/api/v1/health')
    ready, _ = probe(args.api_url.rstrip('/')+'/api/v1/health/ready')
    version_status, version = probe(args.api_url.rstrip('/')+'/api/v1/health/version')
    log_ok = False
    counts = summarize_logs([])
    try:
        command = ['docker', 'compose', '--env-file', str(args.env_file), '-f', str(args.compose_file),
                   'logs', '--no-color', '--since', '5m', '--tail', '10000', 'api']
        logs = subprocess.run(command, capture_output=True, text=True, timeout=20, check=True)
        counts = summarize_logs((logs.stdout+'\n'+logs.stderr).splitlines())
        log_ok = True
    except (OSError, subprocess.SubprocessError):
        pass
    backup = backup_health(args.backup_directory, now)
    alerts = []
    if live != 200: alerts.append('API_UNAVAILABLE')
    if ready != 200: alerts.append('API_NOT_READY')
    if version_status != 200 or version.get('environment') != 'production': alerts.append('PRODUCTION_IDENTITY_UNVERIFIED')
    if not log_ok: alerts.append('LOG_COLLECTION_FAILED')
    if counts['http_5xx'] or counts['database_errors']: alerts.append('SERVER_ERRORS_IN_WINDOW')
    if not backup['healthy']: alerts.append('BACKUP_UNHEALTHY')
    if counts['write_conflicts'] or counts['write_rejections']: alerts.append('WRITE_REVIEW_REQUIRED')
    result = dict(time=now.isoformat(), status='attention' if alerts else 'healthy',
                  liveness=live, readiness=ready, log_window_minutes=5, log_tail_limit=10000,
                  counters=counts, backup=backup, alerts=alerts)
    args.output_directory.mkdir(parents=True, exist_ok=True)
    with (args.output_directory/f'monitor-{now:%Y-%m-%d}.jsonl').open('a') as handle:
        handle.write(json.dumps(result)+'\n')
    temporary = args.output_directory/'monitor-latest.json.tmp'
    temporary.write_text(json.dumps(result, indent=2))
    temporary.replace(args.output_directory/'monitor-latest.json')
    print(json.dumps(result))
    return 1 if alerts else 0


if __name__ == '__main__':
    raise SystemExit(main())
