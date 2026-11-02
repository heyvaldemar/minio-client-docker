#!/usr/bin/env bash
# Raise Go modules in patches/mc-go-modules.patch.
#
#   scripts/bump-modules.sh <module>[@version] ...
#
# For the day scripts/cve-gate.sh stops a publish on a Go module with a fixed
# version. In the Go image the Dockerfile pins: mc is cloned at the pinned
# tag and commit, the current patch is applied, each module named here is
# raised (to its newest release when no version is given) with whatever Go's
# minimal version selection raises with it, go mod tidy runs, and the result,
# a change to go.mod and go.sum only, replaces the patch. Then mc is built and
# its unit tests run. Read the diff before committing it, and let CI run mc's
# functional tests on the image.
set -euo pipefail
[ "$#" -gt 0 ] || { echo "usage: bump-modules.sh <module>[@version] ..." >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2016  # $BUILDPLATFORM is the Dockerfile's text, matched as it is
go_image="$(sed -nE 's/^FROM --platform=\$BUILDPLATFORM (golang:[^ ]+@sha256:[0-9a-f]{64}) AS build$/\1/p' "$ROOT/Dockerfile")"
pin="$(sed -nE 's/^ARG MC=(RELEASE\.[0-9TZ-]+:[0-9a-f]{40})$/\1/p' "$ROOT/Dockerfile" | sort -u)"
if [ -z "$go_image" ] || [ "$(printf '%s\n' "$pin" | grep -c .)" != 1 ]; then
  echo "cannot read the Go image or the one mc pin from the Dockerfile" >&2; exit 1
fi

mods=()
for m in "$@"; do
  [[ "$m" =~ ^[a-zA-Z0-9._~/-]+(@v[0-9A-Za-z.+-]+|@latest)?$ ]] || { echo "not a module path: $m" >&2; exit 2; }
  case "$m" in *@*) mods+=("$m") ;; *) mods+=("$m@latest") ;; esac
done

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
cp "$ROOT/patches/mc-go-modules.patch" "$out/current.patch"
docker run --rm -v "$out:/out" -e PIN="$pin" -e CGO_ENABLED=0 -e GOTOOLCHAIN=local "$go_image" bash -c '
  set -euo pipefail
  tag="${PIN%%:*}"; sha="${PIN#*:}"
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" https://github.com/minio/mc.git /src/mc
  [ "$(git -C /src/mc rev-parse HEAD)" = "$sha" ] || { echo "minio/mc ${tag} is not commit ${sha}" >&2; exit 1; }
  cd /src/mc
  git apply /out/current.patch
  go get "$@"
  go mod tidy
  git diff -- go.mod go.sum > /out/new.patch
  [ "$(git diff --name-only | sort | tr "\n" " ")" = "go.mod go.sum " ] || { echo "go changed more than go.mod and go.sum" >&2; exit 1; }
  go build -mod=readonly -trimpath -o /dev/null .
  # vet stays off: newer Go vets format strings mc wrote before that check.
  go test -mod=readonly -vet=off -count=1 ./...
' bash "${mods[@]}"
cp "$out/new.patch" "$ROOT/patches/mc-go-modules.patch"
git -C "$ROOT" --no-pager diff --stat -- patches/
echo "Read the change to the module versions, then commit it:"
git -C "$ROOT" --no-pager diff -U0 -- patches/mc-go-modules.patch | grep -E '^[-+][-+]\t[a-z]' || true
