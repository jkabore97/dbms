#!/usr/bin/env bash
#
# Builds the Flutter web bundle with the Supabase credentials compiled in.
#
# The credentials live in .env at the repo root and are read here rather than
# typed on a command line, so they never land in shell history. The
# publishable key is meant to reach the browser — RLS is what protects the
# data — but the secret/service_role key must never pass through this script.
#
# Usage:  scripts/build-web.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="$repo_root/.env"

if [[ ! -f "$env_file" ]]; then
  echo "No .env at $env_file — copy .env.example and fill it in." >&2
  exit 1
fi

# Only the two keys the app is built with, and only from lines that assign
# them, so nothing else in .env is pulled into this shell. The trailing \r is
# stripped because a file saved on Windows would otherwise compile a carriage
# return into the URL, and the app would fail every request with nothing on
# screen to explain why.
# Trimming is done with sed rather than xargs: xargs would also try to parse
# quotes and backslashes, and an unbalanced quote in a key would abort the
# build with an error about the wrong thing entirely.
read_env() {
  sed -n "s/^$1=//p" "$env_file" \
    | tail -n 1 \
    | tr -d '\r' \
    | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

supabase_url="$(read_env SUPABASE_URL)"
supabase_key="$(read_env SUPABASE_PUBLISHABLE_KEY)"

if [[ -z "$supabase_url" || -z "$supabase_key" ]]; then
  echo "SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must both be set in .env." >&2
  echo "Built without them, the app starts but the login screen has no server to talk to." >&2
  exit 1
fi

# Supabase has two generations of keys and the dangerous one looks different
# in each. A current secret key announces itself: sb_secret_... A legacy
# service_role key is a JWT, and the words "service_role" are inside the
# base64 payload where no substring match on the raw key will ever see them —
# so the payload is decoded and the role claim read directly.
key_role() {
  local key="$1" payload
  [[ "$key" == eyJ*.*.* ]] || return 0
  payload="${key#*.}"
  payload="${payload%%.*}"
  payload="${payload//-/+}"
  payload="${payload//_//}"
  # base64 -d rejects unpadded input; JWTs strip the padding.
  case $(( ${#payload} % 4 )) in
    2) payload="$payload==" ;;
    3) payload="$payload=" ;;
  esac
  printf '%s' "$payload" | base64 -d 2>/dev/null || true
}

if [[ "$supabase_key" == sb_secret_* ]] \
  || [[ "$(key_role "$supabase_key")" == *'"service_role"'* ]]; then
  echo "That is a secret key — it bypasses RLS entirely." >&2
  echo "Only the publishable key (or the legacy anon key) belongs in a browser bundle." >&2
  exit 1
fi

cd "$repo_root/app"
flutter pub get
flutter build web --release \
  --dart-define=SUPABASE_URL="$supabase_url" \
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$supabase_key"

echo
echo "Built app/build/web."
echo "Deploy it:  wrangler deploy --config workers/kaj-app/wrangler.toml"
