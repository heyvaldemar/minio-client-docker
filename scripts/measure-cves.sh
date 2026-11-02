#!/usr/bin/env bash
# CVE counts for this image and the one it replaces, written to
# reports/cves.md and reports/cves.json.
#
#   scripts/measure-cves.sh <this image>
#
# An image name with a slash is read from its registry; one without, from
# the local Docker engine.
#
# The one it replaces: the last versioned bitnami/minio-client, frozen in
# August 2025 as bitnamilegacy/minio-client:2025.7.21-debian-12-r3.
# bitnami/minio-client has no tags left, and MinIO publishes no mc image, so
# there is nothing else to count. Counted by Trivy, the operating system's
# packages and the Go modules inside mc, once per CVE and package, all
# severities, and separately the critical and high findings that already have
# a fixed version: those are the ones a rebuild removes, and a frozen image
# never gets.
set -euo pipefail
OURS="${1:?usage: measure-cves.sh <this image>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/ci-images.pins"
out="$ROOT/reports"; mkdir -p "$out"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
PLATFORM="${PLATFORM:-linux/amd64}"

rows=(
  "bitnamilegacy/minio-client:2025.7.21-debian-12-r3|the last versioned bitnami/minio-client, frozen 2025-08-19"
  "$OURS|this image"
)

docker volume create trivy-cache >/dev/null
md="| Image | What it is | OS | Critical | High | Medium | Low | Critical and high with a fix |\n|---|---|---|---|---|---|---|---|\n"
json="["
for row in "${rows[@]}"; do
  IFS='|' read -r ref what <<<"$row"
  # A published image is read from its registry, a local build from the
  # Docker engine: Docker Desktop's containerd store cannot export a
  # multi-platform image it holds only one platform of.
  case "$ref" in */*) src=remote ;; *) src=docker ;; esac
  # The database comes from Google's mirror: ghcr.io answers a fresh CI
  # runner with 429 often enough to fail a weekly run.
  if ! docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache \
      "$TRIVY_IMAGE" image --quiet --format json --scanners vuln --platform "$PLATFORM" --image-src "$src" \
      --db-repository mirror.gcr.io/aquasec/trivy-db:2 \
      "$ref" > "$work/t.json" 2> "$work/t.err"; then
    echo "Trivy failed on $ref:" >&2; tail -n 20 "$work/t.err" >&2; exit 1
  fi
  cells="$(python3 -I - "$work/t.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
os_ = d.get("Metadata", {}).get("OS", {})
seen, c, fixable = set(), {}, 0
for r in d.get("Results", []):
    for v in r.get("Vulnerabilities") or []:
        k = (v["VulnerabilityID"], v["PkgName"])
        if k in seen:
            continue
        seen.add(k)
        c[v["Severity"]] = c.get(v["Severity"], 0) + 1
        if v["Severity"] in ("CRITICAL", "HIGH") and v.get("FixedVersion"):
            fixable += 1
print("|".join([("%s %s" % (os_.get("Family", "?"), os_.get("Name", ""))).strip()]
               + [str(c.get(s, 0)) for s in ("CRITICAL", "HIGH", "MEDIUM", "LOW")] + [str(fixable)]))
PY
)"
  IFS='|' read -r osname crit high med low fix <<<"$cells"
  md+="| \`$ref\` | $what | $osname | $crit | $high | $med | $low | $fix |\n"
  json+="{\"image\":\"$ref\",\"os\":\"$osname\",\"critical\":$crit,\"high\":$high,\"medium\":$med,\"low\":$low,\"fixable_critical_high\":$fix},"
  # Which findings, for the frozen image: the table says how many, this says
  # where they are (Debian, Go's standard library, or a module inside mc).
  python3 -I - "$work/t.json" > "$out/$(printf '%s' "$ref" | tr '/:' '__').fixable.txt" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
seen = set()
for r in d.get("Results", []):
    for v in r.get("Vulnerabilities") or []:
        k = (v["VulnerabilityID"], v["PkgName"])
        if k in seen or v["Severity"] not in ("CRITICAL", "HIGH") or not v.get("FixedVersion"):
            continue
        seen.add(k)
        print("%s\t%s\t%s\t%s -> %s\t%s" % (v["Severity"], v["VulnerabilityID"], v["PkgName"], v.get("InstalledVersion", ""), v["FixedVersion"], r.get("Target", "")))
PY
done
json="${json%,}]"
trivy_v="$(docker run --rm "$TRIVY_IMAGE" --version | head -1)"
{
  printf '# CVE counts, %s\n\n' "$(date -u +%Y-%m-%d)"
  printf 'Platform %s. %s, no VEX, databases read the same day. Counted once per CVE and package.\n\n' "$PLATFORM" "$trivy_v"
  printf '%b' "$md"
} > "$out/cves.md"
printf '%s\n' "$json" | python3 -I -m json.tool > "$out/cves.json"
cat "$out/cves.md"
