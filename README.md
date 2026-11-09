# minio-client Docker Image

[![Publish Docker Image](https://github.com/heyvaldemar/minio-client-docker/actions/workflows/publish.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/minio-client-docker/actions/workflows/publish.yml)
[![Docker Pulls](https://img.shields.io/docker/pulls/heyvaldemar/minio-client.svg)](https://hub.docker.com/r/heyvaldemar/minio-client)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/heyvaldemar/minio-client-docker/badge)](https://scorecard.dev/viewer/?uri=github.com/heyvaldemar/minio-client-docker)
[![Licences: MIT, mc AGPL-3.0](https://img.shields.io/badge/licences-MIT%20%7C%20mc%20AGPL--3.0-blue.svg)](#licences)

mc, the MinIO Client, from its last release, rebuilt every week, signed, and laid out like `bitnami/minio-client`, so a Job, a compose service or a script written for that image runs on this one unchanged. Not affiliated with or endorsed by MinIO, Inc. or Broadcom.

Checked 2026-11-09:

- `bitnami/minio-client` has no tags left. Its last versioned Debian image lives on, frozen since 2025-08-19, as `bitnamilegacy/minio-client:2025.7.21-debian-12-r3`; that repository counted 971,594 pulls.
- MinIO archived [minio/mc](https://github.com/minio/mc) after RELEASE.2025-08-13T08-35-41Z, and `minio/mc` on Docker Hub returns 404.
- The client command in the NOTES of Bitnami's last MinIO chart, bitnamicharts/minio 17.0.21, fails as published: its `clientImage` tag no longer exists. With an image that does exist, it still fails. `-- admin info minio` hands `admin` to Bitnami's entrypoint as the program to run, so the working form names `run.sh`, as in the examples below.

```bash
# mc through Bitnami's run.sh: the MINIO_SERVER_* variables set an alias called `minio` first
docker run --rm \
  -e MINIO_SERVER_HOST=minio.example.internal \
  -e MINIO_SERVER_ROOT_USER -e MINIO_SERVER_ROOT_PASSWORD \
  heyvaldemar/minio-client:latest /opt/bitnami/scripts/minio-client/run.sh mb --ignore-existing minio/backups

# which mc this is, how it was built, and which Go modules were raised
docker run --rm --entrypoint cat heyvaldemar/minio-client:latest /opt/bitnami/minio-client/build.txt
```

A Kubernetes Job, configured from a Secret:

```yaml
containers:
  - name: make-bucket
    image: heyvaldemar/minio-client:2025.8.13
    args: ["/opt/bitnami/scripts/minio-client/run.sh", "mb", "--ignore-existing", "minio/backups"]
    env:
      - {name: MINIO_SERVER_HOST, value: minio}
      - name: MINIO_SERVER_ROOT_USER
        valueFrom: {secretKeyRef: {name: minio, key: root-user}}
      - name: MINIO_SERVER_ROOT_PASSWORD
        valueFrom: {secretKeyRef: {name: minio, key: root-password}}
    securityContext: {readOnlyRootFilesystem: true, allowPrivilegeEscalation: false, capabilities: {drop: [ALL]}}
    volumeMounts:
      - {name: mc, mountPath: /.mc}     # an emptyDir: where mc keeps the alias
```

In bitnamicharts/minio, `clientImage` takes the same values: `registry: docker.io`, `repository: heyvaldemar/minio-client`, `tag: "2025.8.13"`, with `global.security.allowInsecureImages: true`, the switch Bitnami's charts need for an image from outside their catalogue.

## Tags

| Tag | What it is | Moves |
|---|---|---|
| `2025.8.13` | mc RELEASE.2025-08-13T08-35-41Z | every week and on every change here, with Debian's security updates, Go's, and the Go modules' |
| `latest` | the same image | as `2025.8.13` |

Every tag moves, so a pinned tag keeps receiving security fixes. For an image that never changes, pin its digest:

```bash
docker buildx imagetools inspect heyvaldemar/minio-client:2025.8.13 --format '{{.Manifest.Digest}}'
```

Images are `linux/amd64` and `linux/arm64`, on Debian 13.

## What this is, and what it is not

A rebuild of the last mc release, RELEASE.2025-08-13T08-35-41Z at commit [`7394ce0`](https://github.com/minio/mc/tree/7394ce0dd2a80935aded936b09fa12cbb3cb8096), built with a current Go and with the Go modules listed in [`patches/mc-go-modules.patch`](patches/mc-go-modules.patch) raised to versions without their known vulnerabilities. The patch changes go.mod and go.sum and nothing else; the build refuses a patch that touches anything more. It is not a fork with new features: mc's own code is MinIO's, as released.

How it is kept:

- **Only Go and module bumps.** Nothing else changes in mc. Debian's updates arrive with the weekly rebuild, Go's with a bump of the pinned Go image, and a module's with `scripts/bump-modules.sh`. Each change passes mc's unit tests and MinIO's own functional tests before it can merge.
- **Publication stops when the CVE gate fails.** A build that carries a critical or high finding with a fixed version is not published (`scripts/cve-gate.sh`). The published tags then stay as they were until a bump lands. A finding in mc's own code that no bump can remove is reported in the [security policy](SECURITY.md)'s advisories and is not hidden.
- **What a user should do:** pin by digest, and watch this repository's releases. `mc --version` names the release with `.rebuild` appended, `RELEASE.2025-08-13T08-35-41Z.rebuild`, because these are not MinIO's bytes.

## A drop-in for bitnami/minio-client

How bitnami/minio-client is used: a Job or a compose service gives it `MINIO_SERVER_HOST` and the server's root user and password, and runs Bitnami's `run.sh` with mc's arguments. Older setups use the `_ACCESS_KEY` and `_SECRET_KEY` names, and any of them can come as a `_FILE`. The entrypoint's setup step turns those variables into an alias called `minio`. Or the user replaces the command and calls mc from `PATH`. This image keeps what that depends on:

- the user `1001`, the working directory `/opt/bitnami/minio-client`, and `HOME=/` with `/.mc` writable by group 0 for mc's configuration;
- Bitnami's entrypoint and run scripts as entrypoint and command, and every script under `/opt/bitnami/scripts` a user's own script may source, from Bitnami's last release of this image;
- `PATH` with `/opt/bitnami/minio-client/bin` first, where mc is;
- the build `SHELL` an image built `FROM` it inherits: bash with `errexit`, `nounset` and `pipefail`.

What is different, on purpose:

- **Debian 13**, where Bitnami's image was Debian 12.
- **mc RELEASE.2025-08-13T08-35-41Z**, built with Go 1.27 and the raised modules. The frozen image has RELEASE.2025-07-21T05-28-08Z, built with Go 1.24.6.
- **Root owns mc, its directories and the scripts.** The user mc runs as can run them and cannot replace them. In Bitnami's image, group 0, its user's group, could write to `/opt/bitnami`.
- **Two changes to Bitnami's scripts, both named in [`bitnami/NOTICE`](bitnami/NOTICE).** The welcome line in `libbitnami.sh` names this image, not Bitnami's. `libminioclient.sh` hands mc the secret key on stdin, where Bitnami's put it in mc's arguments and every user on the host could read it with `ps`.

**It is checked, not claimed.** These run on every build, and nothing is published unless all pass:

- `tests/drop-in-test.sh` compares the image with `bitnamilegacy/minio-client:2025.7.21-debian-12-r3`. It checks the same user, working directory, entrypoint, command, build `SHELL`, `HOME` and `PATH`; the same scripts; `/.mc`; no setuid file; and every executable on its `PATH`, or a reason in [`tests/drop-in-absent.tsv`](tests/drop-in-absent.tsv). Then both images run against one MinIO server in each way above: the root variables, the older names, a password from a `_FILE`, a port and an upper-case scheme, a chart's locked-down securityContext, and mc from `PATH` with its own alias. They must give the same answers for a bucket, an object, its size and contents, and a user's policy.
- `tests/mc-functional.sh` runs MinIO's own `functional-tests.sh`, from the commit this builds, with this image's mc against a MinIO server. It covers buckets, objects (empty, small and multipart), metadata, storage classes, moves, presigned URLs, mirror, find, watch, aliases, users and policies.
- `tests/charts-e2e.sh` installs bitnamicharts/minio 17.0.21 on a fresh kind cluster with this image as its `clientImage`. It runs a Job configured from the chart's own Secret as the example above is: a bucket made, a file copied in, its size read back. The same test passes on `bitnamilegacy/minio-client:2025.7.21-debian-12-r3`, which is how the test itself was checked.
- `tests/vendored-scripts.sh` checks every script under `bitnami/scripts` against bitnami/containers at the commit [`bitnami/NOTICE`](bitnami/NOTICE) names: byte for byte, but the two changes above, each of which must differ by exactly its `tests/<name>.diff`.

## CVE counts

Counted by Trivy 0.76.1 on 2026-11-09 in [run 42658394330](https://github.com/heyvaldemar/minio-client-docker/actions/runs/42658394330), on the images as published, on `linux/amd64`, once per CVE and package, Debian's packages and the Go binaries, with no vendor statements applied:

| Image | What it is | OS | Critical | High | Medium | Low | Critical and high with a fix |
|---|---|---|---|---|---|---|---|
| `bitnamilegacy/minio-client:2025.7.21-debian-12-r3` | the last versioned `bitnami/minio-client`, frozen 2025-08-19 | Debian 12.11 | 19 | 145 | 264 | 148 | 126 |
| `heyvaldemar/minio-client:latest` | this image | Debian 13.7 | 0 | 47 | 74 | 67 | 0 |

- **The last column is the one a rebuild controls.** Every high finding left in this image is one Trivy lists no fixed version for. `scripts/cve-gate.sh` refuses to publish an image that carries one with a fix, so the week a fix ships, the next build carries it or nothing is published.
- **The frozen image only gets worse.** Of its 126 fixable findings, 53 are in mc as the SBOM Bitnami shipped inside the image describes it: 26 in the Go standard library and 27 in Go modules, 11 of those in golang.org/x/crypto. The other 73 are in Debian 12's packages, 32 of those in Perl's and 18 in OpenSSL's. None of those fixes will reach it.
- **There is no current Bitnami image to compare.** `bitnami/minio-client` has no tags left, so the frozen image is the only Bitnami minio-client anyone can still pull.

The workflow counts again after every publish and keeps the table as a run artifact.

## Nothing you used yesterday disappears today

Before anything is published, each build is compared with the image already published as `latest` (`scripts/contract-test.sh`). The comparison covers every executable on its `PATH`; every script and mc; its user, working directory, entrypoint, command, build `SHELL`, `HOME` and `PATH`; an mc release at least as new; and the same Debian release. A removal has to be named in `tests/contract-removed.tsv` and in the changelog.

Each test is shown the breaks it exists for (`tests/plants.tsv`, twenty of them, run in CI before anything is published):

- the image running as root, or its user able to replace mc or the scripts;
- the working directory moved, or mc as the entrypoint, so the variables set no alias;
- Bitnami's libraries left out, mc gone from `PATH`, `HOME` moved, no `/.mc`;
- the build `SHELL` lost, setuid bits kept, the AGPL licence and the patch left out of the image;
- mc from another commit, mc's own code changed, a Go module whose bytes are not the ones go.sum records, the module patch left out;
- Bitnami's default port, `_FILE` support or older variable names broken;
- one of Bitnami's scripts changed without a word in `bitnami/NOTICE`.

## Supply chain

- **mc is built from source**, cloned at its release tag and refused unless the tag names the commit pinned in the `Dockerfile`. go.sum checks every Go module the build downloads.
- The Go image (Go 1.27 on Debian 13) and Debian 13 slim are each pinned by digest. Dependabot moves the digests by pull request, gated by the full build and tests.
- Every package is brought to the newest version Debian's security archive has at build time, the base's own included.
- Every published digest is signed with cosign, keyless, by this repository's workflow, and every tag's signature is verified in the same run. SBOM (SPDX) and SLSA provenance are attached, and build provenance is attested in [GitHub Attestations](https://github.com/heyvaldemar/minio-client-docker/attestations).
- Trivy scans every published image, Debian's packages and the Go modules inside mc, and reports critical and high fixable findings to the Security tab.
- Every GitHub Action is pinned to a commit SHA, except the SLSA generator, which `release-assets.yml` calls by tag (`@v2.1.0`) because it verifies its own reference at run time and refuses a SHA.

```bash
cosign verify heyvaldemar/minio-client:2025.8.13 \
  --certificate-identity-regexp "https://github.com/heyvaldemar/minio-client-docker/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com"
```

## Licences

- **mc** is MinIO's, under the GNU AGPL v3 (or later). Its licence, CREDITS and NOTICE are in the image under `/opt/bitnami/minio-client/licenses`, beside the patch this image applies, `mc-go-modules.patch`. The source of the mc in an image is named by the image's labels:
  - `io.heyvaldemar.mc.source` is mc's commit;
  - `io.heyvaldemar.mc.patch` is the patch at this repository's commit;
  - `org.opencontainers.image.source` and `org.opencontainers.image.revision` name that commit.

  Every release of this repository carries the patch and the `Dockerfile` in its signed archive.
- **Bitnami's scripts** under `bitnami/scripts` are Broadcom's, under the Apache License 2.0 in [`bitnami/LICENSE`](bitnami/LICENSE); [`bitnami/NOTICE`](bitnami/NOTICE) names their source and the one change.
- **This repository's own files** are MIT.

MinIO is a trademark of MinIO, Inc. Bitnami is a trademark of Broadcom. Both names are used here only to say what this image works with and replaces.

## Build it yourself

```bash
docker build -t minio-client:2025.8.13 .
./tests/drop-in-test.sh minio-client:2025.8.13
./tests/mc-functional.sh minio-client:2025.8.13
./scripts/cve-gate.sh minio-client:2025.8.13
./tests/charts-e2e.sh minio-client:2025.8.13      # needs kind and helm
```

## Bugs, changes and vulnerabilities

Report a bug or ask for a change in [issues](https://github.com/heyvaldemar/minio-client-docker/issues). Pull requests are welcome: every test above runs on them before anything can merge. Report a vulnerability privately, as [SECURITY.md](SECURITY.md) describes.

## Related

[heyvaldemar/os-shell](https://hub.docker.com/r/heyvaldemar/os-shell), [heyvaldemar/kubectl](https://hub.docker.com/r/heyvaldemar/kubectl) and [heyvaldemar/jmx-exporter](https://hub.docker.com/r/heyvaldemar/jmx-exporter) do the same for `bitnami/os-shell`, `bitnami/kubectl` and `bitnami/jmx-exporter`: rebuilt weekly, signed, and checked against the last versioned Bitnami image.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · CNCF Ambassador · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
