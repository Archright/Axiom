# Hermetic Build / Policy Verification

This document defines the decoupled build and policy-verification workflow for
Axiom-core.

## Principle

Building and policy enforcement are **separate concerns**:

1. **Build Tier** — the host (or CI worker) compiles Axiom binaries using a
   persistent Nim cache.
2. **Artifact Tier** — the compiled binaries (`bin/`, `build/`).
3. **Enforcement Tier** — a minimal Docker image runs a pre-built binary under
   `strace` and audits every `execve` against
   `src/policy/build_constraint.nim`.

The container is a **pure policy verifier**; it never compiles code.

## Quick start

```bash
# 1. Build on the host using persistent ~/.cache/nim.
nimble build

# 2. Verify a built binary under hermetic policy enforcement.
bin/hermetic-build bin/axiom --version
```

## Toolchain alignment

The Dockerfile pins the Nim version via a `NIM_VERSION` build argument
(default `2.2.10`). The host and CI must use the same version. If
`bin/hermetic-build` detects a different host Nim version it prints a warning.

The runtime image is based on `ubuntu:22.04`, matching
`.circleci/Dockerfile.ci`, so glibc and libssl versions stay aligned between
host build and container runtime.

## Cache invalidation

Local builds rely on Nim's own incremental cache in `~/.cache/nim`. The
compiler invalidates individual source files automatically when they change.

In CI, the cache key is deterministic:

```text
axiom-nimcache-v1-{nimble.lock}-{config.nims}-{axiom.nimble}-{branch}
```

The key changes when the toolchain, dependency graph, or project
configuration changes. Source-only edits reuse the CI cache and rely on Nim's
internal invalidation.

## `bin/hermetic-build`

```bash
bin/hermetic-build <pre-built-binary> [args...]
```

- Builds the policy verifier Docker image if missing or stale.
- Rejects old build-style invocations such as `nimble build` with a migration
  message.
- Mounts the repository root read-only at `/src` inside the container.
- Runs the binary under `hermetic_entry` + `strace`.
- Returns the binary's exit code, or `1` if a policy violation is detected.

### Migration from old workflow

Old:

```bash
bin/hermetic-build nimble build
```

New:

```bash
nimble build
bin/hermetic-build bin/axiom --version
```

## Policy enforcement

`tools/hermetic_entry.nim` traces `execve` syscalls and delegates auditing to
`src/policy/build_constraint.nim`. Forbidden interpreters (python3, bash, sh,
dash, perl, ruby, node) and any external binary outside the allow-list cause
immediate failure.

The binary being verified itself is allowed to start once; any additional
unexpected `execve` is a violation.

## CI integration

In CI (CircleCI), the `gates` job runs on a **machine executor** (ubuntu-2204
VM) with Docker Layer Caching enabled. The build happens inside the
`ghcr.io/archright/axiom-ci` container via the `run-in-ci-image` reusable
command. Policy verification runs directly on the machine using native Docker
CLI — no DinD, no remote Docker daemon.

The sequence is:

1. Checkout + git setup
2. `docker pull` CI image (DLC warm-up, runs immediately after checkout)
3. CircleCI cache restore
4. Build inside CI image container (`nimble install` + `nim c -r gate_hook.nim ci`)
5. Hermetic policy verification (`bin/hermetic-build bin/axiom --version`)
6. PBT advisory inside CI image container
7. CircleCI cache save

File ownership is fixed after each container run (`sudo chown -R`) to handle
the UID mismatch between the container (root, UID 0) and the machine host
(circleci, UID confirmed at first deployment).

See `.circleci/continue.yml` for the full configuration.

## Files

- `Dockerfile.build` — multi-stage verifier image.
- `bin/hermetic-build` — host-side wrapper.
- `tools/hermetic_entry.nim` — container entrypoint.
- `src/policy/build_constraint.nim` — policy rules.
