#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Public frontend configuration only. Never supply database/JWT credentials here.
readonly FLUTTER_REVISION=6655482ec06e547f90abf8ae7590466f4415978d
readonly FLUTTER_TAG=3.47.1
sdk_dir="$(mktemp -d /tmp/zedbiz-flutter.XXXXXX)"
trap 'rm -rf -- "$sdk_dir"' EXIT
git clone --depth 1 --branch "$FLUTTER_TAG" https://github.com/flutter/flutter.git "$sdk_dir"
[[ "$(git -C "$sdk_dir" rev-parse HEAD)" == "$FLUTTER_REVISION" ]] || { echo 'Flutter revision mismatch'; exit 1; }
export PATH="$sdk_dir/bin:$PATH"
export CI=true
flutter config --no-analytics
flutter precache --web
flutter pub get --enforce-lockfile
version="$(sed -n 's/^version: //p' pubspec.yaml | tr -d '\r')"
[[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]] || { echo 'Invalid application version'; exit 1; }
app_version="${BASH_REMATCH[1]}"
app_build="${BASH_REMATCH[2]}"
commit="$(git rev-parse HEAD)"
flutter build web --release --no-pub --no-wasm-dry-run --no-web-resources-cdn \
  --dart-define=API_BASE_URL=https://zedbiz-backend.onrender.com \
  --dart-define=APP_ENV=production \
  --dart-define=API_REQUEST_TIMEOUT_SECONDS=90 \
  --dart-define="APP_VERSION=$app_version" \
  --dart-define="APP_BUILD_NUMBER=$app_build" \
  --dart-define="GIT_COMMIT=$commit"
# Cloudflare's _headers file is not Render configuration.
for file in index.html main.dart.js flutter_bootstrap.js offline_shell.js sqlite3.wasm drift_worker.dart.js; do
  test -s "build/web/$file" || { echo "Missing required output: $file"; exit 1; }
done
