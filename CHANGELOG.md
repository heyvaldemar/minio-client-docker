# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The images are tagged by mc release; these versions describe the image and
the pipeline that builds it.

## [Unreleased]

<!-- conformance: first release not before 2026-11-09 - one new Docker Hub image a week -->

### Added

- **heyvaldemar/minio-client: mc RELEASE.2025-08-13T08-35-41Z, the last MinIO Client release, rebuilt on Debian 13 every week.** It is built from source at commit `7394ce0` with Go 1.27, and `patches/mc-go-modules.patch` raises the Go modules that carried a fixed vulnerability (grpc, golang.org/x/net and x/crypto, prometheus, klauspost/compress, and what they pull with them). The patch changes go.mod and go.sum only. Tags `2025.8.13` and `latest`; `linux/amd64` and `linux/arm64`. Not affiliated with or endorsed by MinIO, Inc.
- **A drop-in for bitnami/minio-client, checked on every build** against `bitnamilegacy/minio-client:2025.7.21-debian-12-r3`. The checks cover:
  - user `1001`, the working directory `/opt/bitnami/minio-client`, Bitnami's entrypoint and `run.sh`, `HOME=/` with `/.mc`, `PATH`, the build `SHELL`, and Bitnami's scripts from their last release;
  - every executable on its `PATH`, or a reason in `tests/drop-in-absent.tsv`;
  - both images against one MinIO server, configured each way bitnami/minio-client is used, giving the same answers.
- **MinIO's own functional tests for mc**, from the commit this builds, run on this image's mc against a MinIO server.
- **Bitnami's own MinIO chart on kind** (bitnamicharts/minio 17.0.21) with this image as its client, in a Job configured from the chart's Secret.
- **Bitnami's scripts checked against their source**: byte for byte, but the one welcome line `bitnami/NOTICE` names.
- **No fixable critical or high finding**: `scripts/cve-gate.sh` refuses an image that carries one, in Debian's packages, in Go, or in a Go module inside mc.
- **A contract with the published image**: nothing a Job used under a tag disappears from it without a line in `tests/contract-removed.tsv`.
- **Every digest signed** with cosign, keyless, and every tag's signature verified after signing. SBOM, SLSA provenance and a GitHub build attestation are attached; Trivy scans the published image, and CVE counts against the image it replaces follow every publish.
- **Every test shown the breaks it exists for**: twenty planted violations in `tests/plants.tsv`, run in CI before anything is published.

[Unreleased]: https://github.com/heyvaldemar/minio-client-docker/commits/main
