# syntax=docker/dockerfile:1.7

# ──────────────────────────────────────────────────────────────────────────────
# heyvaldemar/minio-client: mc, the MinIO Client, rebuilt from its last release
# every week, signed, and laid out like bitnami/minio-client, so a Job, a
# compose service or a script written for that image runs on this one
# unchanged: user 1001, the working directory /opt/bitnami/minio-client,
# Bitnami's entrypoint and run scripts, the MINIO_SERVER_* variables that set
# the `minio` alias, and HOME=/ with /.mc for mc's configuration.
#
# MinIO archived github.com/minio/mc after RELEASE.2025-08-13T08-35-41Z and no
# longer publishes an image of it; Bitnami's bitnami/minio-client has no tags
# left. This is that last release, rebuilt. Not affiliated with or endorsed by
# MinIO, Inc. or Broadcom.
# ──────────────────────────────────────────────────────────────────────────────

# ──────────────────────────────────────────────────────────────────────────────
# Stage 1: mc. Cloned at its last release tag and refused unless the tag names
# the commit pinned here. patches/mc-go-modules.patch then raises the Go
# modules that carry a vulnerability with a fixed version, and changes nothing
# else: it touches go.mod and go.sum only. go.sum checks every module the
# build downloads. Built with the Go pinned here on the build platform and
# cross-compiled, with mc's own release flags, so `mc --version` names the
# release and its commit; the release tag carries `.rebuild`, because these
# are not MinIO's bytes. scripts/bump-modules.sh writes the patch again.
# ──────────────────────────────────────────────────────────────────────────────
FROM --platform=$BUILDPLATFORM golang:1.27-trixie@sha256:c65ecfe613b539ac74c62a4c3b2c27e8f8a6076384c8f27e8a3c0f3be17cc385 AS build

ARG TARGETOS
ARG TARGETARCH
ARG MC=RELEASE.2025-08-13T08-35-41Z:7394ce0dd2a80935aded936b09fa12cbb3cb8096

ENV CGO_ENABLED=0 \
    GOTOOLCHAIN=local \
    GOFLAGS=-mod=readonly

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY patches/mc-go-modules.patch /patches/

WORKDIR /src

RUN set -euo pipefail; \
    tag="${MC%%:*}"; sha="${MC#*:}"; \
    git -c advice.detachedHead=false clone -q --depth 1 --branch "$tag" https://github.com/minio/mc.git mc; \
    [ "$(git -C mc rev-parse HEAD)" = "$sha" ] || { echo "minio/mc ${tag} is not commit ${sha}" >&2; exit 1; }; \
    git -C mc apply --check /patches/mc-go-modules.patch; \
    git -C mc apply /patches/mc-go-modules.patch; \
    [ "$(git -C mc diff --name-only | sort | tr '\n' ' ')" = "go.mod go.sum " ] || { echo "the patch changes more than go.mod and go.sum" >&2; exit 1; }; \
    stamp="${tag#RELEASE.}"; \
    version="$(sed -E 's/T([0-9]{2})-([0-9]{2})-([0-9]{2})Z$/T\1:\2:\3Z/' <<<"$stamp")"; \
    ldflags="-s -w -X github.com/minio/mc/cmd.Version=${version} -X github.com/minio/mc/cmd.CopyrightYear=${stamp:0:4}"; \
    ldflags+=" -X github.com/minio/mc/cmd.ReleaseTag=${tag}.rebuild -X github.com/minio/mc/cmd.CommitID=${sha} -X github.com/minio/mc/cmd.ShortCommitID=${sha:0:12}"; \
    GOOS="$TARGETOS" GOARCH="$TARGETARCH" go -C mc build -trimpath -buildvcs=false -tags kqueue -ldflags "$ldflags" -o /out/mc .; \
    mkdir -p /out/licenses; \
    cp mc/LICENSE /out/licenses/mc-LICENSE; \
    cp mc/CREDITS /out/licenses/mc-CREDITS; \
    cp mc/NOTICE /out/licenses/mc-NOTICE; \
    cp /patches/mc-go-modules.patch /out/licenses/mc-go-modules.patch; \
    { \
      printf 'mc %s %s\n' "$tag" "$sha"; \
      printf 'built with %s, every Go module checked against go.sum\n' "$(go env GOVERSION)"; \
      printf 'Go modules raised by mc-go-modules.patch:\n'; \
      sed -n '/^+++ b\/go.mod/,/^diff /p' /patches/mc-go-modules.patch | sed -nE 's/^\+\t([^ ]+) (v[^ ]+).*/  \1 \2/p'; \
    } > /out/build.txt; \
    cat /out/build.txt

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2: the image. Debian 13, with what bitnami/minio-client installed
# beside mc (CA certificates, jq, procps) and Bitnami's own scripts from
# bitnami/scripts.
# ──────────────────────────────────────────────────────────────────────────────
FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4 AS final

ARG TARGETARCH
ARG MC=RELEASE.2025-08-13T08-35-41Z:7394ce0dd2a80935aded936b09fa12cbb3cb8096
ARG APP_VERSION=2025.8.13
ARG VCS_REF=unknown
ARG BUILD_DATE=unknown
ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Every package is brought to the newest version the suite's security archive
# has at build time, the base's own included: the weekly rebuild is how a fix
# Debian has published reaches this image, and scripts/cve-gate.sh refuses to
# publish one that still carries a fixed critical or high finding. No file
# keeps a setuid or setgid bit, as in Bitnami's image.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get -y upgrade \
 && apt-get install -y --no-install-recommends ca-certificates jq procps \
 && rm -rf /var/lib/apt/lists/* \
 && find / -xdev -perm /6000 -type f -exec chmod a-s {} +

COPY bitnami/scripts/ /opt/bitnami/scripts/
COPY --from=build /out/mc /opt/bitnami/minio-client/bin/mc
COPY --from=build /out/licenses/ /opt/bitnami/minio-client/licenses/
COPY bitnami/LICENSE /opt/bitnami/minio-client/licenses/bitnami-scripts-LICENSE
COPY bitnami/NOTICE /opt/bitnami/minio-client/licenses/bitnami-scripts-NOTICE
COPY --from=build /out/build.txt /opt/bitnami/minio-client/build.txt

# Not Bitnami's way, and on purpose: Bitnami's postunpack.sh makes
# /opt/bitnami/minio-client writable by group 0, the group its user 1001 is
# in, so that user could replace mc. Here root owns mc and its directories,
# and only mc's configuration directory /.mc is writable by group 0, as it
# was there.
RUN mkdir -p /.mc \
 && chmod 0775 /.mc \
 && chmod -R go-w /opt/bitnami

ENV HOME=/ \
    PATH=/opt/bitnami/minio-client/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    OS_ARCH=${TARGETARCH} \
    OS_FLAVOUR=debian-13 \
    OS_NAME=linux \
    APP_VERSION=${APP_VERSION} \
    BITNAMI_APP_NAME=minio-client

# The source this image's mc was built from, and the patch applied to it, as
# the AGPL asks: mc's commit, and this repository's patch at the commit that
# built the image. Both are also in /opt/bitnami/minio-client/licenses.
LABEL org.opencontainers.image.title="minio-client" \
      org.opencontainers.image.description="mc, the MinIO Client, rebuilt from its last release on Debian 13, rebuilt weekly, signed; a drop-in for bitnami/minio-client. Not affiliated with or endorsed by MinIO, Inc." \
      org.opencontainers.image.authors="Vladimir Mikhalev <v@valdemar.ai>" \
      org.opencontainers.image.vendor="heyvaldemar" \
      org.opencontainers.image.source="https://github.com/heyvaldemar/minio-client-docker" \
      org.opencontainers.image.documentation="https://github.com/heyvaldemar/minio-client-docker#readme" \
      org.opencontainers.image.url="https://hub.docker.com/r/heyvaldemar/minio-client" \
      org.opencontainers.image.licenses="AGPL-3.0-or-later AND Apache-2.0 AND MIT" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      io.heyvaldemar.mc.release="${MC%%:*}" \
      io.heyvaldemar.mc.source="https://github.com/minio/mc/tree/${MC#*:}" \
      io.heyvaldemar.mc.patch="https://github.com/heyvaldemar/minio-client-docker/blob/${VCS_REF}/patches/mc-go-modules.patch"

# What an image built FROM this one inherits for its RUN lines, as
# bitnami/minio-client set it: a failing command, an unset variable or a
# failing pipe stops the build.
SHELL ["/bin/bash", "-o", "errexit", "-o", "nounset", "-o", "pipefail", "-c"]

WORKDIR /opt/bitnami/minio-client
USER 1001
ENTRYPOINT ["/opt/bitnami/scripts/minio-client/entrypoint.sh"]
CMD ["/opt/bitnami/scripts/minio-client/run.sh"]
