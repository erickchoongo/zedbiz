from datetime import datetime, timezone, timedelta
import hashlib
import importlib.util
import json
from pathlib import Path

spec = importlib.util.spec_from_file_location('pilot_monitor', Path(__file__).resolve().parents[2]/'scripts/pilot_monitor.py')
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


def test_monitor_counts_errors_without_copying_payloads():
    lines = ['api | '+json.dumps(row) for row in [
        {'status': 503, 'path': '/api/v1/businesses/{id}/sales', 'method': 'POST', 'secret': 'must-not-escape'},
        {'error_type': 'OperationalError'},
        {'status': 409, 'path': '/api/v1/businesses/{id}/expenses', 'method': 'POST'},
        {'status': 403, 'path': '/api/v1/businesses/{id}/sales', 'method': 'POST'},
    ]]
    result = monitor.summarize_logs(lines+['not-json', '{}', '[]'])
    assert result == {'http_5xx': 1, 'database_errors': 1, 'write_conflicts': 1, 'write_rejections': 1}
    assert 'must-not-escape' not in json.dumps(result)


def test_backup_monitor_detects_stale_tampered_and_failed_backups(tmp_path):
    now = datetime.now(timezone.utc)
    archive = tmp_path/'test.dump'
    archive.write_bytes(b'archive fixture')
    record = {'file': archive.name, 'time': now.isoformat(), 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest()}
    def save():
        (tmp_path/'latest-backup.json').write_text(json.dumps(record))
    save()
    attempt = tmp_path/'last-backup-attempt.json'
    attempt.write_text('{"status":"success"}')
    assert monitor.backup_health(tmp_path, now)['healthy']
    assert not monitor.backup_health(tmp_path, now+timedelta(hours=26))['healthy']
    attempt.write_text('{"status":"failed"}')
    assert not monitor.backup_health(tmp_path, now)['healthy']
    attempt.write_text('{"status":"success"}')
    archive.write_bytes(b'tampered')
    assert not monitor.backup_health(tmp_path, now)['healthy']
    record['file'] = '../outside.dump'
    save()
    assert not monitor.backup_health(tmp_path, now)['healthy']
