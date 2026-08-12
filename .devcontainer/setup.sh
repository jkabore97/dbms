#!/usr/bin/env bash
#
# Runs once when the Codespace is created.
#
# Installs Flutter by cloning the stable branch rather than through a
# devcontainer feature — the clone is predictable and its failure modes are
# obvious, which matters when the only terminal you have is in a browser tab.

set -euo pipefail

echo "=============================================="
echo " Setting up the Kaj development environment"
echo " This takes about 5 minutes. It runs once."
echo "=============================================="

# ---------- system packages ----------
echo ""
echo "==> Installing system packages"
sudo apt-get update -qq
sudo apt-get install -y -qq \
    curl git unzip xz-utils zip libglu1-mesa \
    postgresql-client \
    > /dev/null

# ---------- Flutter ----------
if [ ! -d "$HOME/flutter" ]; then
    echo ""
    echo "==> Installing Flutter (stable)"
    git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

# Make flutter available in this shell and in every future one.
export PATH="$HOME/flutter/bin:$PATH"
if ! grep -q 'flutter/bin' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/flutter/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo ""
echo "==> Warming up Flutter (first run builds its tooling)"
flutter --version
flutter config --no-analytics > /dev/null 2>&1 || true

# ---------- project dependencies ----------
if [ -f app/pubspec.yaml ]; then
    echo ""
    echo "==> Installing app dependencies"
    (cd app && flutter pub get)
fi

# ---------- CLIs ----------
echo ""
echo "==> Installing Cloudflare CLI (wrangler)"
npm install -g wrangler > /dev/null 2>&1 || echo "   (wrangler install failed — not critical)"

echo ""
echo "==> Installing Claude Code"
npm install -g @anthropic-ai/claude-code > /dev/null 2>&1 || echo "   (claude-code install failed — not critical)"

# ---------- done ----------
cat <<'BANNER'

==============================================
 Ready.

 Useful commands:

   cd app && flutter analyze      check the code
   cd app && ./scripts/serve.sh   run the app on port 8080
   claude                         start Claude Code in this repo
   psql "$SUPABASE_DB_URL"        connect to the database

 Use serve.sh rather than `flutter run` directly: it compiles in the
 Supabase address and key. A build made without them opens on
 "Serveur non configuré" and cannot sign anyone in.

 Secrets belong in Codespaces secrets, not in files:
   github.com/settings/codespaces
 SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) are the
 ones serve.sh reads. Codespaces secrets are separate from Actions secrets —
 setting one does not set the other.

==============================================

BANNER
