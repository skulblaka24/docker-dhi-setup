#!/bin/sh
# pin-digests.sh
# ─────────────────────────────────────────────────────────────────────────────
# Run this script once after `docker login dhi.io` to automatically replace
# all <FILL_DIGEST> placeholders in docker-compose.yml with real sha256 digests.
#
# Usage:
#   chmod +x pin-digests.sh
#   ./pin-digests.sh
# ─────────────────────────────────────────────────────────────────────────────

set -eu

COMPOSE_FILE="docker-compose.yml"

get_digest() {
  image="$1"
  docker pull "$image" --quiet
  docker inspect --format='{{index .RepoDigests 0}}' "$image" \
    | sed 's/.*@sha256://'
}

echo "Pulling images and resolving digests..."

POSTGRES_DIGEST=$(get_digest "dhi.io/postgres:15-alpine3.22")
REDIS_DIGEST=$(get_digest "dhi.io/redis:7-debian13")
NGINX_DIGEST=$(get_digest "dhi.io/nginx:1.29.6-alpine3.23")

echo "Building API image..."
docker build -t dhi-taskapi:latest ./api
API_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' dhi-taskapi:latest 2>/dev/null \
  || docker inspect --format='{{.Id}}' dhi-taskapi:latest | sed 's/sha256://')

echo ""
echo "Pinning digests in ${COMPOSE_FILE}..."

# Use a temp file to avoid in-place sed portability issues
cp "$COMPOSE_FILE" "${COMPOSE_FILE}.bak"

perl -pe "
  s|dhi\.io/postgres:15-alpine3\.22\@sha256:<FILL_DIGEST>|dhi.io/postgres:15-alpine3.22\@sha256:${POSTGRES_DIGEST}|g;
  s|dhi\.io/redis:7-debian13\@sha256:<FILL_DIGEST>|dhi.io/redis:7-debian13\@sha256:${REDIS_DIGEST}|g;
  s|dhi\.io/nginx:1\.29\.6-alpine3\.23\@sha256:<FILL_DIGEST>|dhi.io/nginx:1.29.6-alpine3.23\@sha256:${NGINX_DIGEST}|g;
" "${COMPOSE_FILE}.bak" > "$COMPOSE_FILE"

echo ""
echo "Done. Digests pinned:"
echo "  postgres : sha256:${POSTGRES_DIGEST}"
echo "  redis    : sha256:${REDIS_DIGEST}"
echo "  nginx    : sha256:${NGINX_DIGEST}"
echo ""
echo "Backup saved as ${COMPOSE_FILE}.bak"
echo "Pin the API digest manually once you push dhi-taskapi to a registry."
