#!/usr/bin/env bash
# Does this image work as the client of Bitnami's own MinIO chart?
#
#   tests/charts-e2e.sh <image>
#
# Bitnami's last MinIO chart (bitnamicharts/minio 17.0.21, August 2025) names
# bitnami/minio-client as its clientImage, a tag that no longer exists. This
# installs that chart on a fresh kind cluster, with its server from
# bitnamilegacy (frozen with it) and this image as its clientImage, then runs
# the client the way a Kubernetes Job uses bitnami/minio-client: the server
# from the chart's Service, the root user and password from the chart's own
# Secret as MINIO_SERVER_* variables, Bitnami's run.sh with mc's arguments,
# and a chart's securityContext: user and group 1001, a read-only root
# filesystem, no capabilities, emptyDir volumes for /.mc and /tmp.
#
# The Job makes a bucket, copies a file in and reads its size back; each step
# is its own container, as each run.sh call is one mc command. The chart's
# NOTES must name this image for its client command.
#
# Any image can be named, bitnamilegacy/minio-client:2025.7.21-debian-12-r3
# included: that is how this test is checked against the image it replaces.
set -euo pipefail
IMAGE="${1:?usage: charts-e2e.sh <image>}"
CLUSTER="${CLUSTER:-minio-client-e2e}"
KIND_NODE="${KIND_NODE:-}"
MINIO_CHART="${MINIO_CHART:-17.0.21}"
SERVER_REPO="${SERVER_REPO:-bitnamilegacy/minio}"
SERVER_TAG="${SERVER_TAG:-2025.7.23-debian-12-r3}"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
ok() { echo "OK: $*"; }

repo="${IMAGE%:*}"; tag="${IMAGE##*:}"
[ "$repo" != "$IMAGE" ] || { echo "name the image with a tag, for example minio-client:2025.8.13" >&2; exit 2; }

cleanup() { [ -n "${KEEP_CLUSTER:-}" ] || kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true; }
# Keep the script's own exit status: the trap must not turn a failure into 0.
on_exit() { local rc=$?; cleanup; exit "$rc"; }
trap on_exit EXIT
kind delete cluster --name "$CLUSTER" >/dev/null 2>&1 || true
node=()
[ -z "$KIND_NODE" ] || node=(--image "$KIND_NODE")
kind create cluster --name "$CLUSTER" ${node[@]+"${node[@]}"} --wait 120s >/dev/null
# A local image goes in by `kind load`; a published one is pulled by the node.
pull=IfNotPresent
if docker image inspect "$IMAGE" >/dev/null 2>&1 && [ "${repo#*/}" = "$repo" ]; then
  kind load docker-image "$IMAGE" --name "$CLUSTER" >/dev/null
  pull=Never
fi
export KUBECONFIG
KUBECONFIG="$(mktemp)"
kind get kubeconfig --name "$CLUSTER" >"$KUBECONFIG"

# The chart as published, but for the images: the server from bitnamilegacy,
# the client this one, the console off (its image is frozen too, and the
# client does not need it). Bitnami's charts refuse an image from outside
# their catalogue unless told it is meant (global.security.allowInsecureImages);
# that is the switch a user flips too.
if helm install minio oci://registry-1.docker.io/bitnamicharts/minio --version "$MINIO_CHART" \
  --set global.security.allowInsecureImages=true \
  --set image.registry=docker.io \
  --set image.repository="$SERVER_REPO" \
  --set image.tag="$SERVER_TAG" \
  --set clientImage.registry=docker.io \
  --set clientImage.repository="$repo" \
  --set clientImage.tag="$tag" \
  --set console.enabled=false \
  --wait --timeout 8m >/dev/null; then
  ok "bitnamicharts/minio $MINIO_CHART is Ready with ${SERVER_REPO}:${SERVER_TAG}"
else
  kubectl get pods -o wide >&2 || true
  kubectl describe pods >&2 || true
  bad "bitnamicharts/minio $MINIO_CHART did not become Ready"
  exit 1
fi

notes="$(helm get notes minio)"
if printf '%s\n' "$notes" | grep -qF -- "--image docker.io/${repo}:${tag}"; then
  ok "the chart's NOTES name this image for the client: $(printf '%s\n' "$notes" | grep -F -- '--image' | sed 's/^ *//')"
else
  bad "the chart's NOTES do not name docker.io/${repo}:${tag}"
fi

size="$(docker run --rm --entrypoint wc "$IMAGE" -c /opt/bitnami/scripts/minio-client/run.sh 2>/dev/null | cut -d' ' -f1 || true)"
[ -n "$size" ] || size="$(kubectl run size-probe --rm -i --restart=Never --image "docker.io/${repo}:${tag}" --image-pull-policy "$pull" --command -- wc -c /opt/bitnami/scripts/minio-client/run.sh 2>/dev/null | cut -d' ' -f1)"

step() { # name, then mc's arguments
  local name="$1"; shift
  printf '        - name: %s\n          image: docker.io/%s:%s\n          imagePullPolicy: %s\n          args: [%s]\n' \
    "$name" "$repo" "$tag" "$pull" "\"/opt/bitnami/scripts/minio-client/run.sh\", \"--no-color\"$(printf ', "%s"' "$@")"
  cat <<'YAML'
          env:
            - name: MINIO_SERVER_HOST
              value: minio
            - name: MINIO_SERVER_ROOT_USER
              valueFrom: {secretKeyRef: {name: minio, key: root-user}}
            - name: MINIO_SERVER_ROOT_PASSWORD
              valueFrom: {secretKeyRef: {name: minio, key: root-password}}
          securityContext:
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities: {drop: [ALL]}
          volumeMounts:
            - {name: mc, mountPath: /.mc}
            - {name: tmp, mountPath: /tmp}
YAML
}
{
  cat <<'YAML'
apiVersion: batch/v1
kind: Job
metadata:
  name: client
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      securityContext:
        runAsUser: 1001
        runAsGroup: 1001
        fsGroup: 1001
        runAsNonRoot: true
        seccompProfile: {type: RuntimeDefault}
      volumes:
        - {name: mc, emptyDir: {}}
        - {name: tmp, emptyDir: {}}
      initContainers:
YAML
  step mb mb --ignore-existing minio/e2e
  step cp cp /opt/bitnami/scripts/minio-client/run.sh minio/e2e/run.sh
  echo "      containers:"
  step stat --json stat minio/e2e/run.sh
} | kubectl apply -f - >/dev/null

if kubectl wait --for=condition=complete job/client --timeout=180s >/dev/null 2>&1; then
  ok "the client Job completed: mb, cp and stat through run.sh, each configured by the MINIO_SERVER_* variables"
else
  kubectl get pods -l job-name=client -o wide >&2 || true
  for c in mb cp stat; do kubectl logs "job/client" -c "$c" >&2 2>&1 || true; done
  bad "the client Job did not complete"
fi
got="$(kubectl logs job/client -c stat 2>/dev/null | sed -n '/^{/p' | jq -r '.size' 2>/dev/null || true)"
if [ -n "$size" ] && [ "$got" = "$size" ]; then
  ok "the object reads back at the size written ($got bytes)"
else
  bad "the object reads back at '${got}' bytes, not '${size}'"
fi

[ "$fail" -eq 0 ] || exit 1
echo "Bitnami's MinIO chart works with ${IMAGE} as its client."
