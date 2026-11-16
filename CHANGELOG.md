# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The images are tagged by mc release; these versions describe the image and
the pipeline that builds it.

## [Unreleased]

_(no unreleased changes yet)_

## [1.0.3] - 2026-11-16

### Changed

- **A tag never names an unsigned image.** The build pushes the image by digest, with no tag (`push-by-digest=true`). The signing action signs it, attests it, checks that the signature is on Docker Hub and verifies as this workflow, and only then points the tags at it, with `docker buildx imagetools create --prefer-index=false`, which copies the index as it is, so each tag names the signed digest. Until 1.0.2 the tags moved with the push: anything that failed between the push and the signature left them on an unsigned image for a while. A run that cannot sign now names nothing, and every tag keeps naming what it named. The signing test shows it: with signing failing, `latest` stays on the earlier run's signed image and a tag new in that run never appears. The same as heyvaldemar/aws-kubectl-docker 2.3.2.
- **Cosign is installed before anything is pushed.** The build job installs cosign v2.6.1 before the push, and the signing action finds it there; a failed install fails the job before even the untagged image is pushed.

## [1.0.2] - 2026-11-15

### Added

- **Every tag a run pushes is read back from Docker Hub after signing.** For each one the run resolves the digest the tag names now, and requires that digest's cosign signature (`sha256-<digest>.sig`, HTTP 200) and a `cosign verify` that passes: for the digest this run pushed, as this run's exact workflow identity and commit; for a digest another run has moved the tag to since, as this repository's publish workflow on any ref. A missing signature fails the job. A digest this run built is then signed again; a digest it did not build never is. It also runs after a push refused half way: the build reports no digest then, so the tags it had already moved are reported and fail the job, but are not signed. What it found goes to the run summary (`scripts/verify-published.sh`).
- **The signing steps are shown each failure they exist for, before anything is published.** Signing, attesting and reading back are one action, `.github/actions/sign-attest-verify`, the same as in heyvaldemar/aws-kubectl-docker 2.3.1. The build job runs it after its push, and a new `signing` job runs it six times on throwaway images in a registry on the runner, signed with keys made there. The cases: nothing planted; the real attestation step failing (the job has no OIDC token, so the step fails before it contacts anything; the image is signed before the failure, and the job still fails); signing failing; signing skipped without an error, where the read-back alone fails the job and signs the digest; a tag another run moved to an image signed by a stranger's key (the job fails, and that image is left as it is); and a push that stopped half way (the job fails, nothing is signed). Nothing reaches Docker Hub, GitHub's attestation store or Sigstore's public log. The build waits for it, and so does the required check.

### Changed

- **`SECURITY.md` and the image's `org.opencontainers.image.authors` label give the public contact address**, and `SECURITY.md` links GitHub's form for a private vulnerability report directly. The label reaches the published images with the next weekly rebuild; nothing else in them changes.

### Fixed

- **Signing no longer depends on the build attestation.** The cosign steps came after `actions/attest-build-provenance` and ran only if it succeeded: the order in which heyvaldemar/aws-kubectl-docker shipped an unsigned image on 2 November 2026, when Rekor, Sigstore's transparency log, answered its attestation 502 and three of its tags named that image for 37 hours. No run here hit it. The pushed digest is now signed first, then attested; a failed attestation still fails the job, after the signature exists. It is signed once, not once per tag (the signature belongs to the digest either way), and a failed attempt is tried again twice. The step that verified every tag's signature came after signing with the same condition, so it would have been skipped too; the read-back below replaces it.

## [1.0.1] - 2026-11-12

### Fixed

- **The daily pin check no longer reports an index pushed again over the same builds as drift.** `freshness.yml` compared each pinned base digest with the digest its tag names now and failed on any difference, so a publisher pushing the index again over the very same images (a platform added, an attestation rewritten) turned it red for an image that had not changed. It now also compares the builds this image is made from under both digests: linux/amd64 alone when every stage from that base is built on the runner (`--platform=$BUILDPLATFORM` or `${BUILDPLATFORM}`), linux/amd64 and linux/arm64 when any stage is built for each published platform, as the fleet's triage judges a re-pushed base. The same builds pass with a notice naming both digests; a new build, or one that cannot be read, still fails.

### Security

- **Go 1.27.4 builds mc.** `golang:1.27-trixie` moved from `sha256:af1bfc26…` to `sha256:c47c3fda…`, Go 1.27.3 to Go 1.27.4, a security release: CVE-2026-97054 in the standard library's net/http server, which mc's binary carries, and eleven in how the go command, the compiler and the linker handle cgo and linker flags. mc's own code and `patches/mc-go-modules.patch` are unchanged.

## [1.0.0] - 2026-11-09

### Added

- **heyvaldemar/minio-client: mc RELEASE.2025-08-13T08-35-41Z, the last MinIO Client release, rebuilt on Debian 13 every week.** It is built from source at commit `7394ce0` with Go 1.27, and `patches/mc-go-modules.patch` raises the Go modules that carried a fixed vulnerability (grpc, golang.org/x/net and x/crypto, prometheus, klauspost/compress, and what they pull with them). The patch changes go.mod and go.sum only. Tags `2025.8.13` and `latest`; `linux/amd64` and `linux/arm64`. Not affiliated with or endorsed by MinIO, Inc.
- **A drop-in for bitnami/minio-client, checked on every build** against `bitnamilegacy/minio-client:2025.7.21-debian-12-r3`. The checks cover:
  - user `1001`, the working directory `/opt/bitnami/minio-client`, Bitnami's entrypoint and `run.sh`, `HOME=/` with `/.mc`, `PATH`, the build `SHELL`, and Bitnami's scripts from their last release;
  - every executable on its `PATH`, or a reason in `tests/drop-in-absent.tsv`;
  - both images against one MinIO server, configured each way bitnami/minio-client is used, giving the same answers.
- **MinIO's own functional tests for mc**, from the commit this builds, run on this image's mc against a MinIO server.
- **Bitnami's own MinIO chart on kind** (bitnamicharts/minio 17.0.21) with this image as its client, in a Job configured from the chart's Secret.
- **Bitnami's scripts checked against their source**: byte for byte, but the two changes `bitnami/NOTICE` names.
- **No fixable critical or high finding**: `scripts/cve-gate.sh` refuses an image that carries one, in Debian's packages, in Go, or in a Go module inside mc.
- **A contract with the published image**: nothing a Job used under a tag disappears from it without a line in `tests/contract-removed.tsv`.
- **Every digest signed** with cosign, keyless, and every tag's signature verified after signing. SBOM, SLSA provenance and a GitHub build attestation are attached; Trivy scans the published image, and CVE counts against the image it replaces follow every publish.
- **Every test shown the breaks it exists for**: twenty planted violations in `tests/plants.tsv`, run in CI before anything is published.

### Security

- **The MinIO secret key is not on a command line.** Bitnami's `libminioclient.sh` configures its aliases with `mc alias set <alias> <url> <user> <secret key>`, the secret key in `mc`'s arguments, where every user on the host reads it with `ps`. Given three arguments, `mc` reads the secret key from stdin instead, so the script now hands it over that way from bash's own `printf`. It is the second file changed from Bitnami's: `bitnami/NOTICE` says so, and `tests/vendored-scripts.sh` requires each changed file to differ by exactly its `tests/<name>.diff`. The drop-in test's own `mc alias set` does the same, against both images.

[Unreleased]: https://github.com/heyvaldemar/minio-client-docker/compare/v1.0.3...HEAD
[1.0.3]: https://github.com/heyvaldemar/minio-client-docker/releases/tag/v1.0.3
[1.0.2]: https://github.com/heyvaldemar/minio-client-docker/releases/tag/v1.0.2
[1.0.1]: https://github.com/heyvaldemar/minio-client-docker/releases/tag/v1.0.1
[1.0.0]: https://github.com/heyvaldemar/minio-client-docker/releases/tag/v1.0.0
