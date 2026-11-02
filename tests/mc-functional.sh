#!/usr/bin/env bash
# mc's own functional tests, run on this image against a MinIO server.
#
#   tests/mc-functional.sh <image>
#
# MinIO wrote functional-tests.sh to check a build of mc against a real
# server: buckets, objects small, empty and multipart, metadata, storage
# classes, moves, presigned URLs, cat, copy, mirror, find, watch, aliases,
# users and policies. This runs the script from the very commit the
# Dockerfile builds, with this image's mc, against the server Bitnami's last
# MinIO chart runs. It is what says the raised Go modules left mc working.
#
# The script calls curl for its presigned-URL tests, and bitnami/minio-client
# never carried curl, so it runs in an image built FROM this one with curl
# added: which also builds on this image the way a user's own image would.
set -euo pipefail
IMAGE="${1:?usage: mc-functional.sh <image>}"
SERVER="${MINIO_SERVER_IMAGE:-bitnamilegacy/minio:2025.7.23-debian-12-r3}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

commit="$(sed -nE 's/^ARG MC=RELEASE\.[0-9TZ-]+:([0-9a-f]{40})$/\1/p' "$ROOT/Dockerfile" | sort -u)"
[ "$(printf '%s\n' "$commit" | grep -c .)" = 1 ] || { echo "the Dockerfile does not pin one mc commit" >&2; exit 1; }

work="$(mktemp -d)"
net="mc-functional-$$"
tag="mc-functional:$$"
cleanup() {
  docker rm -f "$net-server" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
  docker rmi -f "$tag" >/dev/null 2>&1 || true
  rm -rf "$work"
}
on_exit() { local rc=$?; cleanup; exit "$rc"; }
trap on_exit EXIT

curl -fsSL --retry 3 "https://raw.githubusercontent.com/minio/mc/${commit}/functional-tests.sh" -o "$work/functional-tests.sh"
cat >"$work/Dockerfile" <<EOF
FROM ${IMAGE}
USER 0
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
USER 1001
EOF
docker build -q -t "$tag" "$work" >/dev/null
chmod 0755 "$work"; chmod 0644 "$work/functional-tests.sh"

# A throwaway server's root user and password, made here and never printed.
MINIO_ROOT_USER="root$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
MINIO_ROOT_PASSWORD="$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')"
ACCESS_KEY="$MINIO_ROOT_USER" SECRET_KEY="$MINIO_ROOT_PASSWORD"
export MINIO_ROOT_USER MINIO_ROOT_PASSWORD ACCESS_KEY SECRET_KEY
docker network create "$net" >/dev/null
docker run -d --name "$net-server" --network "$net" -e MINIO_ROOT_USER -e MINIO_ROOT_PASSWORD "$SERVER" >/dev/null

# Bitnami's server image starts MinIO once to configure it, stops it, then
# starts it for good; ready is after that, when it answers.
for _ in $(seq 1 90); do
  docker logs "$net-server" 2>&1 | grep -q '\*\* Starting MinIO \*\*' && break
  sleep 1
done
ready=false
for _ in $(seq 1 60); do
  if docker run --rm --network "$net" --entrypoint bash "$tag" -c "curl -fsS -o /dev/null http://$net-server:9000/minio/health/ready" 2>/dev/null; then ready=true; break; fi
  sleep 1
done
$ready || { docker logs "$net-server" 2>&1 | tail -20 >&2; echo "the MinIO server never became ready" >&2; exit 1; }

if docker run --rm --network "$net" -e SERVER_ENDPOINT="$net-server:9000" -e ACCESS_KEY -e SECRET_KEY -e ENABLE_HTTPS=0 \
    -v "$work/functional-tests.sh:/tests/functional-tests.sh:ro" -w /tmp --entrypoint bash "$tag" /tests/functional-tests.sh >"$work/out" 2>&1; then
  ran="$(grep -cE '^Running [a-z_]+\(\)$' "$work/out" || true)"
  # Its last test is test_admin_users: an exit before it is not a pass.
  grep -qx 'Running test_admin_users()' "$work/out" || { cat "$work/out" >&2; echo "FAIL: the script exited 0 after ${ran} tests, before its last" >&2; exit 1; }
  echo "OK: mc's functional tests from commit ${commit:0:12}, ${ran} of them, pass on this image's mc against ${SERVER}"
else
  tail -40 "$work/out" >&2
  echo "FAIL: mc's functional tests from commit ${commit:0:12} fail on this image's mc" >&2
  exit 1
fi
