#!/usr/bin/env bash
# Are the scripts under bitnami/scripts Bitnami's, as bitnami/NOTICE says?
#
#   tests/vendored-scripts.sh
#
# Fetches bitnami/containers at the commit bitnami/NOTICE names and compares
# every script with the file at the same path there (prebuildfs and rootfs
# together, as Bitnami's image merged them). Each must be byte for byte the
# same, except libbitnami.sh, whose difference must be exactly
# tests/libbitnami.diff: the welcome line that names this image instead of
# Bitnami's. Nothing may be added or missing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
commit="$(grep -oE '\b[0-9a-f]{40}\b' "$ROOT/bitnami/NOTICE" | head -1)"
dir=bitnami/minio-client/2025/debian-12
[ -n "$commit" ] || { echo "bitnami/NOTICE names no commit" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git -C "$work" init -q
git -C "$work" remote add origin https://github.com/bitnami/containers.git
git -C "$work" config core.sparseCheckout true
printf '%s/\n' "$dir" >"$work/.git/info/sparse-checkout"
git -C "$work" fetch -q --depth 1 origin "$commit"
git -C "$work" checkout -q FETCH_HEAD
mkdir "$work/upstream"
cp -R "$work/$dir/prebuildfs/opt/bitnami/scripts/." "$work/upstream/"
cp -R "$work/$dir/rootfs/opt/bitnami/scripts/." "$work/upstream/"

fail=0
if diff <(cd "$work/upstream" && find . -type f | sort) <(cd "$ROOT/bitnami/scripts" && find . -type f | sort) >/dev/null; then
  echo "OK: the same $(find "$ROOT/bitnami/scripts" -type f | wc -l | tr -d ' ') files as bitnami/containers@${commit:0:12}"
else
  echo "FAIL: the file lists differ from bitnami/containers@${commit:0:12}:" >&2
  diff <(cd "$work/upstream" && find . -type f | sort) <(cd "$ROOT/bitnami/scripts" && find . -type f | sort) >&2 || true
  fail=1
fi
while IFS= read -r f; do
  if [ "$f" = ./libbitnami.sh ]; then
    # Not a pipe: diff exits 1 on any difference, which pipefail would take
    # for the comparison's answer.
    if cmp -s <(diff "$work/upstream/$f" "$ROOT/bitnami/scripts/$f") "$ROOT/tests/libbitnami.diff"; then
      echo "OK: libbitnami.sh differs only by the welcome line in tests/libbitnami.diff"
    else
      echo "FAIL: libbitnami.sh differs from Bitnami's by more than tests/libbitnami.diff" >&2; fail=1
    fi
  elif ! cmp -s "$work/upstream/$f" "$ROOT/bitnami/scripts/$f"; then
    echo "FAIL: ${f#./} is not Bitnami's file" >&2; fail=1
  fi
done < <(cd "$work/upstream" && find . -type f | sort)
[ "$fail" -eq 0 ] || exit 1
echo "Every other script is byte for byte Bitnami's."
