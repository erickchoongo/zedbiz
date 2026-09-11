from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess

import pytest


@pytest.mark.skipif(os.name != 'nt', reason='Windows PowerShell wrapper verification')
def test_retention_preserves_unmanaged_files_and_rejects_escape(tmp_path):
    # Execute the real wrapper against a stand-in dump writer, never live backups.
    wrapper = Path(__file__).resolve().parents[2]/'scripts/run-pilot-backup.ps1'
    shutil.copyfile(wrapper, tmp_path/wrapper.name)
    (tmp_path/'backup-postgres.ps1').write_text('''param($EnvFile,$ComposeFile,$BackupDirectory)
$name = 'zedbiz_2099-01-01_000000_' + ([guid]::NewGuid().ToString('N').Substring(0,8)) + '.dump'
$path = Join-Path $BackupDirectory $name
[IO.File]::WriteAllBytes($path, [byte[]](1,2,3))
(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash | Set-Content "$path.sha256"
''')
    directory = tmp_path/'managed'
    directory.mkdir()
    unmanaged = directory/'operator-archive.dump'
    unmanaged.write_bytes(b'keep')
    outside = tmp_path/'outside.dump'
    outside.write_bytes(b'outside')
    now = datetime.now(timezone.utc)
    catalogue = []
    for age in range(1, 41):
        date = now-timedelta(days=age)
        name = f'zedbiz_{date:%Y-%m-%d}_000000_{age:08x}.dump'
        (directory/name).write_bytes(b'fixture')
        (directory/(name+'.sha256')).write_text('fixture')
        catalogue.append({'file': name, 'time': date.isoformat()})
    manifest = directory/'managed-backups.json'
    manifest.write_text(json.dumps(catalogue))
    command = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(tmp_path/wrapper.name),
               '-EnvFile', str(tmp_path/'unused.env'), '-BackupDirectory', str(directory), '-Prune']
    first = subprocess.run(command, capture_output=True, timeout=30)
    assert first.returncode == 0
    kept = json.loads(manifest.read_text(encoding='utf-8-sig'))
    assert 14 <= len(kept) <= 18
    assert unmanaged.read_bytes() == b'keep'
    assert not (directory/catalogue[-1]['file']).exists()
    assert (directory/catalogue[0]['file']).exists()
    kept.append({'file': '../outside.dump', 'time': (now-timedelta(days=1000)).isoformat()})
    manifest.write_text(json.dumps(kept))
    second = subprocess.run(command, capture_output=True, timeout=30)
    assert second.returncode != 0
    assert outside.read_bytes() == b'outside'
    assert json.loads((directory/'last-backup-attempt.json').read_text(encoding='utf-8-sig'))['status'] == 'failed'
