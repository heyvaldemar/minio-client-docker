#!/usr/bin/env bash
# Is this image a drop-in for bitnami/minio-client?
#
#   tests/drop-in-test.sh <image> [<bitnami-image>]
#
# How bitnami/minio-client is used: a Job, a compose service or a one-off
# `docker run` gives it MINIO_SERVER_HOST and the server's root user and
# password (or the older _ACCESS_KEY and _SECRET_KEY names, or any of them as
# a _FILE), and runs /opt/bitnami/scripts/minio-client/run.sh with mc's
# arguments: the entrypoint's setup step turns the variables into an alias
# called `minio` first. Or it replaces the command and calls mc from PATH. So
# the image has to keep the user, working directory, entrypoint, command,
# build SHELL, PATH, HOME and /.mc, Bitnami's scripts under the same paths,
# and mc on PATH. The last versioned Bitnami image
# (bitnamilegacy/minio-client:2025.7.21-debian-12-r3, August 2025) is the
# reference. Every executable on its PATH must be on this image's PATH, unless
# tests/drop-in-absent.tsv names it with the reason.
#
# Then both images are run each of those ways against one MinIO server, and
# must give the same answers.
set -euo pipefail
IMAGE="${1:?usage: drop-in-test.sh <image> [<bitnami-image>]}"
REF="${2:-bitnamilegacy/minio-client:2025.7.21-debian-12-r3}"
# The server Bitnami's last MinIO chart (bitnamicharts/minio 17.0.21) runs,
# frozen like the client: a fixture on a private network, nothing more.
SERVER="${MINIO_SERVER_IMAGE:-bitnamilegacy/minio:2025.7.23-debian-12-r3}"
TESTS="$(cd "$(dirname "$0")" && pwd)"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
ok() { echo "OK: $*"; }

# Compare on one architecture, the host's when the reference has it.
platform="$(docker image inspect -f '{{.Os}}/{{.Architecture}}' "$IMAGE")"
docker pull -q --platform "$platform" "$REF" >/dev/null
docker pull -q --platform "$platform" "$SERVER" >/dev/null
ref_inspect() { docker image inspect --platform "$platform" "$@" 2>/dev/null || docker image inspect "$@"; }

for field in User WorkingDir Entrypoint Cmd Shell; do
  a="$(ref_inspect -f "{{json .Config.$field}}" "$REF")"
  b="$(docker image inspect -f "{{json .Config.$field}}" "$IMAGE")"
  if [ "$a" = "$b" ]; then ok "$field as bitnami/minio-client ($b)"; else bad "$field: bitnami/minio-client $a, this image $b"; fi
done
for var in HOME PATH OS_NAME BITNAMI_APP_NAME; do
  a="$(ref_inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$REF" | sed -n "s/^${var}=//p")"
  b="$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMAGE" | sed -n "s/^${var}=//p")"
  if [ "$a" = "$b" ]; then ok "$var as bitnami/minio-client ($b)"; else bad "$var: bitnami/minio-client '$a', this image '$b'"; fi
done

# Bitnami's scripts, every one a user's own script may source, and mc.
files() { docker run --rm --platform "$2" --entrypoint sh "$1" -c 'cd /opt/bitnami && find scripts minio-client/bin -type f | sort'; }
missing="$(comm -23 <(files "$REF" "$platform") <(files "$IMAGE" "$platform") | tr '\n' ' ')"
if [ -z "$missing" ]; then ok "every script in /opt/bitnami/scripts and mc in /opt/bitnami/minio-client/bin are here"; else bad "in bitnami/minio-client and not here: $missing"; fi

# mc's configuration directory: /.mc, writable by group 0, as there.
if ! docker run --rm --platform "$platform" --entrypoint sh "$REF" -c '[ -d /.mc ] && [ -w /.mc ]' >/dev/null 2>&1; then
  bad "/.mc is not writable by bitnami/minio-client's own user; the test is wrong"
elif docker run --rm --entrypoint sh "$IMAGE" -c '[ -d /.mc ] && [ -w /.mc ]' >/dev/null 2>&1; then
  ok "/.mc exists and the image's own user can write to it, as there"
else
  bad "/.mc is missing or not writable by user 1001"
fi

# Not Bitnami's way, and on purpose: root owns mc, its directories and the
# scripts, so the user mc runs as, 1001 or an arbitrary one in group 0
# (OpenShift), can run them and cannot replace them.
for u in 1001:0 1001:1001 1000650000:0; do
  if docker run --rm --user "$u" --entrypoint sh "$IMAGE" -c '
      for p in /opt/bitnami /opt/bitnami/minio-client /opt/bitnami/minio-client/bin /opt/bitnami/minio-client/bin/mc /opt/bitnami/scripts /opt/bitnami/scripts/minio-client /opt/bitnami/scripts/minio-client/run.sh /opt/bitnami/scripts/libminioclient.sh; do
        [ -e "$p" ] && [ ! -w "$p" ] || exit 1
      done'; then
    ok "user $u can run mc and the scripts and cannot replace them"
  else
    bad "user $u can write to mc, its directories or the scripts"
  fi
done

# No file keeps a setuid or setgid bit, as in Bitnami's image: nothing in it
# can raise the privileges of the user mc runs as.
suid() { docker run --rm --platform "$2" --entrypoint sh "$1" -c 'find / -xdev -perm /6000 -type f 2>/dev/null' | sort; }
if [ -n "$(suid "$REF" "$platform")" ]; then bad "bitnami/minio-client has setuid or setgid files; the test is wrong"
elif [ -z "$(suid "$IMAGE" "$platform")" ]; then ok "no setuid or setgid file, as in bitnami/minio-client"
else bad "setuid or setgid files here: $(suid "$IMAGE" "$platform" | tr '\n' ' ')"; fi

executables() {
  docker run --rm --platform "$2" --entrypoint sh "$1" -c '
    IFS=:
    for d in $PATH; do
      [ -d "$d" ] || continue
      for f in "$d"/*; do [ -f "$f" ] && [ -x "$f" ] && echo "${f##*/}"; done
    done' | sort -u
}
unexplained=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  matched=false
  while IFS=$'\t' read -r pattern _; do
    case "$pattern" in ''|'#'*) continue ;; esac
    # shellcheck disable=SC2053  # the pattern is a glob on purpose
    if [[ "$name" == $pattern ]]; then matched=true; break; fi
  done <"$TESTS/drop-in-absent.tsv"
  $matched || unexplained="$unexplained $name"
done < <(comm -23 <(executables "$REF" "$platform") <(executables "$IMAGE" "$platform"))
if [ -z "$unexplained" ]; then
  ok "every executable on bitnami/minio-client's PATH is here, or named in tests/drop-in-absent.tsv with its reason"
else
  bad "on bitnami/minio-client's PATH and not here, with no reason given:$unexplained"
fi

# ── Both images, against one MinIO server ────────────────────────────────────
net="mc-drop-in-$$"
work="$(mktemp -d)"
cleanup() {
  docker rm -f "$net-server" >/dev/null 2>&1 || true
  docker network rm "$net" >/dev/null 2>&1 || true
  rm -rf "$work"
}
on_exit() { local rc=$?; cleanup; exit "$rc"; }
trap on_exit EXIT
docker network create "$net" >/dev/null

# A throwaway server's root user and password, made here and never printed:
# they reach the containers by name from this environment, not on a command
# line.
MINIO_ROOT_USER="root$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
MINIO_ROOT_PASSWORD="$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')"
export MINIO_ROOT_USER MINIO_ROOT_PASSWORD
export MINIO_SERVER_ROOT_USER="$MINIO_ROOT_USER" MINIO_SERVER_ROOT_PASSWORD="$MINIO_ROOT_PASSWORD"
export MINIO_SERVER_ACCESS_KEY="$MINIO_ROOT_USER" MINIO_SERVER_SECRET_KEY="$MINIO_ROOT_PASSWORD"
printf '%s' "$MINIO_ROOT_PASSWORD" >"$work/password"
chmod 0755 "$work"; chmod 0444 "$work/password"
docker run -d --name "$net-server" --network "$net" --platform "$platform" \
  -e MINIO_ROOT_USER -e MINIO_ROOT_PASSWORD "$SERVER" >/dev/null

RUN_SH=/opt/bitnami/scripts/minio-client/run.sh
# mc through Bitnami's run script, configured by the variables, as a user
# runs bitnami/minio-client: `mc_run <image> [docker options] -- <mc arguments>`.
mc_run() {
  local image="$1"; shift
  local opts=()
  while [ "$1" != -- ]; do opts+=("$1"); shift; done; shift
  MINIO_SERVER_HOST="$net-server" docker run --rm --network "$net" --platform "$platform" -e MINIO_SERVER_HOST \
    "${opts[@]}" "$image" "$RUN_SH" --no-color "$@" 2>"$work/stderr"
}
# Why the last call failed: mc's own error line, which names no credential.
why() { sed -E 's/\x1b\[[0-9;]*m//g' "$work/stderr" | grep -E 'mc: |ERROR' | tail -1 | cut -c1-200; }
# Only mc's own output: Bitnami's scripts log to stderr, mc writes its JSON to stdout.
json() { sed -n '/^{/,$p'; }

# Bitnami's server image starts MinIO in the background to configure it,
# stops it, and then starts it for good: ready is after that last start, and
# three answers in a row that the server is online.
for _ in $(seq 1 90); do
  docker logs "$net-server" 2>&1 | grep -q '\*\* Starting MinIO \*\*' && break
  sleep 1
done
streak=0
for _ in $(seq 1 90); do
  if mc_run "$IMAGE" -e MINIO_SERVER_ROOT_USER -e MINIO_SERVER_ROOT_PASSWORD -- admin info minio --json | json | jq -e '.info.mode == "online"' >/dev/null 2>&1; then
    streak=$((streak + 1)); [ "$streak" -ge 3 ] && break
  else
    streak=0
  fi
  sleep 1
done
[ "$streak" -ge 3 ] || { docker logs "$net-server" 2>&1 | tail -20 >&2; bad "the MinIO server never answered: $(why)"; exit 1; }

# Each way of giving the server, on both images; each must work on
# bitnami/minio-client, or the test is wrong, and then on this image.
check() {
  local what="$1"; shift
  if ! mc_run "$REF" "$@" >/dev/null; then bad "$what: fails on bitnami/minio-client too; the test is wrong ($(why))"; return; fi
  if ! mc_run "$IMAGE" "$@" >/dev/null; then bad "$what: works on bitnami/minio-client and not here ($(why))"; return; fi
  ok "$what"
}
creds=(-e MINIO_SERVER_ROOT_USER -e MINIO_SERVER_ROOT_PASSWORD)
check "MINIO_SERVER_HOST, _ROOT_USER and _ROOT_PASSWORD set the minio alias" "${creds[@]}" -- admin info minio --json
check "the older _ACCESS_KEY and _SECRET_KEY names set it" -e MINIO_SERVER_ACCESS_KEY -e MINIO_SERVER_SECRET_KEY -- admin info minio --json
check "the password read from MINIO_SERVER_ROOT_PASSWORD_FILE" -e MINIO_SERVER_ROOT_USER -e MINIO_SERVER_ROOT_PASSWORD_FILE=/run/secrets/password -v "$work/password:/run/secrets/password:ro" -- admin info minio --json
check "MINIO_SERVER_PORT_NUMBER and an upper-case MINIO_SERVER_SCHEME" "${creds[@]}" -e MINIO_SERVER_PORT_NUMBER=9000 -e MINIO_SERVER_SCHEME=HTTP -- admin info minio --json
# The securityContext a chart gives a client Job: user and group 1001, no new
# privileges, every capability dropped, a read-only root filesystem, and
# emptyDir volumes for mc's configuration and /tmp.
locked=(--user 1001:1001 --read-only --cap-drop ALL --security-opt no-new-privileges --tmpfs /.mc:mode=1777 --tmpfs /tmp:mode=1777)
check "as a chart's Job runs it: user 1001:1001, read-only root, no capabilities" "${locked[@]}" "${creds[@]}" -- admin info minio --json

# The same objects, the same answers. Each image works in its own bucket;
# the object is a file both images carry byte for byte, Bitnami's run.sh.
for side in ref new; do
  img="$REF"; [ "$side" = new ] && img="$IMAGE"
  b="minio/drop-in-$side"
  mc_run "$img" "${locked[@]}" "${creds[@]}" -- mb "$b" >/dev/null || bad "$side: mc mb failed"
  mc_run "$img" "${locked[@]}" "${creds[@]}" -- cp "$RUN_SH" "$b/run.sh" >/dev/null || bad "$side: mc cp failed"
  mc_run "$img" "${locked[@]}" "${creds[@]}" -- ls --json "$b" | json | jq -r '.key' >"$work/$side.ls" || bad "$side: mc ls failed"
  mc_run "$img" "${locked[@]}" "${creds[@]}" -- stat --json "$b/run.sh" | json | jq -r '.size' >"$work/$side.size" || bad "$side: mc stat failed"
  mc_run "$img" "${locked[@]}" "${creds[@]}" -- cat "$b/run.sh" | sha256sum | cut -d' ' -f1 >"$work/$side.sha" || bad "$side: mc cat failed"
  mc_run "$img" "${locked[@]}" "${creds[@]}" -- admin user add minio "user-$side" "$(od -An -N12 -tx1 /dev/urandom | tr -d ' \n')" >/dev/null || bad "$side: mc admin user add failed"
  mc_run "$img" "${locked[@]}" "${creds[@]}" -- admin policy attach minio readonly --user "user-$side" >/dev/null || bad "$side: mc admin policy attach failed"
  mc_run "$img" "${locked[@]}" "${creds[@]}" -- admin user info minio "user-$side" --json | json | jq -r '.policyName' >"$work/$side.policy" || bad "$side: mc admin user info failed"
done
for f in ls size sha policy; do
  if [ -s "$work/ref.$f" ] && cmp -s "$work/ref.$f" "$work/new.$f"; then
    ok "the same answer from both: $f ($(tr '\n' ' ' <"$work/new.$f" | cut -c1-64))"
  else
    bad "different answers for $f: bitnami/minio-client '$(tr '\n' ' ' <"$work/ref.$f")', this image '$(tr '\n' ' ' <"$work/new.$f")'"
  fi
done

# A compose service or a script that replaces the command and calls mc from
# PATH, setting its own alias.
own_alias() {
  SERVER="$net-server" docker run --rm --network "$net" --platform "$platform" -e MINIO_ROOT_USER -e MINIO_ROOT_PASSWORD -e SERVER \
    --entrypoint /bin/sh "$1" -c 'printf "%s\n" "$MINIO_ROOT_PASSWORD" | mc --no-color alias set s "http://$SERVER:9000" "$MINIO_ROOT_USER" >/dev/null && mc --no-color ls s >/dev/null' 2>/dev/null
}
if ! own_alias "$REF"; then bad "mc from PATH fails on bitnami/minio-client too; the test is wrong"
elif own_alias "$IMAGE"; then ok "a command that calls mc from PATH with its own alias works on both"
else bad "mc from PATH, with its own alias, fails here"; fi

# What it is and where its source is: mc's release and commit, the Go that
# built it, and the AGPL's licence, the patch and Bitnami's licence beside it.
built="$(docker run --rm --entrypoint cat "$IMAGE" /opt/bitnami/minio-client/build.txt 2>/dev/null || true)"
case "$built" in
  "mc RELEASE."*"every Go module checked against go.sum"*) ok "built from $(printf '%s\n' "$built" | sed -n '1s/^mc //p'), every Go module checked against go.sum" ;;
  *) bad "the image does not say which mc it built and how: '${built}'" ;;
esac
for f in mc-LICENSE mc-go-modules.patch bitnami-scripts-LICENSE; do
  if docker run --rm --entrypoint test "$IMAGE" -s "/opt/bitnami/minio-client/licenses/$f"; then ok "licenses/$f is in the image"; else bad "licenses/$f is missing"; fi
done
if docker run --rm --entrypoint sh "$IMAGE" -c 'grep -q "GNU AFFERO GENERAL PUBLIC LICENSE" /opt/bitnami/minio-client/licenses/mc-LICENSE'; then ok "mc's licence is the AGPL"; else bad "licenses/mc-LICENSE is not the AGPL"; fi

[ "$fail" -eq 0 ] || { echo "Not a drop-in for bitnami/minio-client." >&2; exit 1; }
echo "A drop-in for bitnami/minio-client."
