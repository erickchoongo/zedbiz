# Local suspension integration test

The automated Flutter widget binding advances a simulated clock. Starting real
HTTP in that clock and using `pumpAndSettle` or wall-clock sleeps can trigger
ApiClient timeouts before socket continuations run. A fixed sleep also cannot
establish that the mutation's subsequent UI refresh finished.

`test/helpers/widget_http.dart` queues widget-originated HTTP and explicitly
completes the real connection and response-body read inside `tester.runAsync`.
The harness then pumps UI continuations and waits for the keyed business action
to have the expected label, be enabled, and have no loading indicator/dialog.
It uses real backend responses, retains production timeout/security settings,
and bounds each real request. Direct API assertions run entirely in `runAsync`.
This is a component integration test, not a browser/PWA end-to-end test.

The confirmation dialog now disposes its controller after its route's exit
transition completes. Temporary diagnostic logging has been removed.

## Run on this workstation

Start Docker Desktop, then from the project root:

```powershell
docker start zedbiz-suspension-test-db
backend/.venv/Scripts/python.exe backend/ops/start_suspension_local.py
```

In another terminal:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mobile/ops/test_admin_access_local.ps1
```

The launcher verifies the loopback Docker binding `127.0.0.1:55432`, database
`zedbiz_suspension_test`, and revision `20261019_0008`. It does not migrate.
The API runs this checkout on port 18001, avoiding older Docker APIs on 8000/8001.

The test runner generates a new fixture and sets `ZEDBIZ_SUSPENSION_FIXTURE`
from that exact invocation. It restores the prior environment value afterward.
The test rejects missing, legacy, older-than-ten-minute, or already-suspended
fixtures and renames a consumed fixture with `.used` before UI mutations.
Credentials remain in local temporary files outside Git; do not share those
files. Every run creates disposable accounts/business data in the isolated DB.

Coverage includes required reason validation, business suspension/reactivation
through the UI, owner access denial/restoration, membership denial/restoration,
global suspension, refresh-token revocation, and a fresh successful login after
global reactivation. Existing membership/user action keys are retained.

Production migration, deployment, and a browser/PWA smoke test are separate
steps requiring approval. Remote suspension cannot be learned while a device
is fully disconnected; the existing bounded offline authorization policy remains.

## Validation on 2026-10-21

- Live workflow: three successful runs using independently generated fixtures.
- `flutter test --no-pub --reporter expanded`: 96 passed, 4 skipped, 0 failed.
  The live test is intentionally skipped without its fixture; it was run
  separately through the runner above.
- `flutter analyze --no-pub`: no issues found.
- `python -m pytest tests/test_admin_suspension.py -q`: 7 passed.
- Local readiness: HTTP 200; verified database revision `20261019_0008`.
- No production changes, migrations, commits, pushes, merges, or deployments.
