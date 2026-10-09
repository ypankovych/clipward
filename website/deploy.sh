#!/usr/bin/env bash
# Deploys the site to the server behind clipward.dev and checks it's live.
set -euo pipefail

HOST="${HOST:-root@137.184.52.244}"
DIR="$(cd "$(dirname "$0")" && pwd)"

rsync -az --delete --exclude '_*.html' --exclude .DS_Store "$DIR/" "$HOST:/opt/clipward-site/"
ssh "$HOST" 'cd /opt/clipward-site && docker compose up -d --build'
curl -fsS https://clipward.dev/ | grep -q '<h1 id="hero-title">Clipward</h1>' && echo "clipward.dev is live"
