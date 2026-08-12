#!/usr/bin/env bash
#
# Serves the app on a port with the Supabase credentials compiled in.
#
#   ./scripts/serve.sh          serve on 8080
#   PORT=3000 ./scripts/serve.sh
#
# In a Codespace the port is forwarded automatically and VS Code offers the
# https URL to open it; make that port Public if you want to try it from a
# phone.
#
# Running `flutter run -d web-server` by hand instead of using this script
# omits the --dart-define flags, and the app then opens on "Serveur non
# configuré" — the credentials are compiled in, not read at runtime, so no
# amount of environment configuration fixes an app that was built without
# them.

set -euo pipefail

# Accept the older names too: SUPABASE_ANON_KEY is what the Supabase dashboard
# still calls the publishable key.
URL="${SUPABASE_URL:-${SUPABASE_PROJECT_URL:-}}"
KEY="${SUPABASE_PUBLISHABLE_KEY:-${SUPABASE_ANON_KEY:-${SUPABASE_KEY:-}}}"

if [ -z "$URL" ] || [ -z "$KEY" ]; then
    missing=""
    [ -n "$URL" ] || missing="$missing SUPABASE_URL"
    [ -n "$KEY" ] || missing="$missing SUPABASE_PUBLISHABLE_KEY"
    cat >&2 <<MSG
Not set in this shell:$missing

In a Codespace these come from Codespaces secrets:
  github.com/settings/codespaces
Add them there, then rebuild the Codespace (or open a new terminal) so the
new values are in the environment.

To try it once without storing anything:
  SUPABASE_URL=https://YOUR-PROJECT.supabase.co \\
  SUPABASE_PUBLISHABLE_KEY=your-key \\
  ./scripts/serve.sh

Serving without them would put a login screen on the port that only says
"Serveur non configuré".
MSG
    exit 1
fi

PORT="${PORT:-8080}"

cd "$(dirname "$0")/.."

# The repo carries lib/ and pubspec.yaml only; the platform folders are
# generated. Creating them is safe to repeat — it never overwrites existing
# files — but it is slow, so only do it when web/ is absent.
if [ ! -d web ]; then
    echo "==> Generating the web platform folder"
    flutter create --platforms=web --project-name kaj_app .
fi

echo "==> Installing dependencies"
flutter pub get

# SQLite compiled to wasm, plus its worker. Without these the page loads and
# then fails when it opens its local database.
if [ ! -f web/sqflite_sw.js ]; then
    echo "==> Installing sqflite web assets"
    dart run sqflite_common_ffi_web:setup
fi

echo "==> Serving on port $PORT"
echo

# 0.0.0.0 rather than localhost: a Codespace forwards the port from outside
# the container, and a server bound to the loopback address is invisible to it.
exec flutter run -d web-server \
    --web-hostname 0.0.0.0 \
    --web-port "$PORT" \
    --dart-define=SUPABASE_URL="$URL" \
    --dart-define=SUPABASE_PUBLISHABLE_KEY="$KEY"
