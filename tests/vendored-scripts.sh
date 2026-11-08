#!/usr/bin/env bash
# Are the scripts under bitnami/scripts Bitnami's, as bitnami/NOTICE says?
#
#   tests/vendored-scripts.sh
#
# Fetches bitnami/containers at the commit bitnami/NOTICE names and compares
# every script with the file at the same path there (prebuildfs and rootfs
# together, as Bitnami's image merged them). Each must be byte for byte the
# same, except a file with a tests/<name>.diff beside this script, whose
# difference must be exactly that: libbitnami.sh's welcome line that names this
# image instead of Bitnami's, and libminioclient.sh handing mc the secret key on
# stdin instead of as an argument. Nothing may be added or missing.
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
  known="$ROOT/tests/$(basename "$f" .sh).diff"
  if [ "${f%/*}" = . ] && [ -f "$known" ]; then
    # Not a pipe: diff exits 1 on any difference, which pipefail would take
    # for the comparison's answer.
    if cmp -s <(diff "$work/upstream/$f" "$ROOT/bitnami/scripts/$f") "$known"; then
      echo "OK: ${f#./} differs only by tests/${known##*/}"
    else
      echo "FAIL: ${f#./} differs from Bitnami's by more than tests/${known##*/}" >&2; fail=1
    fi
  elif ! cmp -s "$work/upstream/$f" "$ROOT/bitnami/scripts/$f"; then
    echo "FAIL: ${f#./} is not Bitnami's file" >&2; fail=1
  fi
done < <(cd "$work/upstream" && find . -type f | sort)
[ "$fail" -eq 0 ] || exit 1
echo "Every other script is byte for byte Bitnami's."
