#!/usr/bin/env bash
#
# verify_b_artifact.sh — SL-08 B/H binding-only verifier (CI quantization)
#
# SL-08 semantics (binding only — NEVER builds): the base-built artifact
# manifest must bind
#   (a) build_sha == B      — the artifact was built from the PR base commit,
#                             and
#   (b) per-file sha256     — every listed artifact file matches its manifest
#                             digest.
#
# Input producer (I-11): the artifact is produced by the epoch Bootstrap build
# stage inside the prefix (per-admission `ci-bootstrap` from B, manifest.txt +
# files emitted together). Old CI is never an implicit producer; this tool
# consumes only the manifest-bound artifact handed to it explicitly.
#
# Canonical source: the inline step "[check] Verify artifact manifest
# (fail-closed — build_sha == B)" in .github/workflows/admission-check.yml
# (job admission-check). This tool is the tracked, testable implementation of
# that predicate so the slice catalog can bind SL-08 to one definition.
#
# Usage:
#   verify_b_artifact.sh <manifest> <expected-build-sha> [<artifact-root>]
#
#   <manifest>            path to the artifact manifest (manifest.txt format:
#                         `build_sha = <40-hex>` header + `sha256  path` lines)
#   <expected-build-sha>  the B commit the artifact must have been built from
#   <artifact-root>       directory artifact paths resolve against (default: .)
#
# Exit codes:
#   0 — binding verified (build_sha == B and every file sha256 matches)
#   1 — binding mismatch (fail-closed; reason on stderr)
#   2 — usage/environment error
#
# Deterministic: same inputs → same verdict. Read-only, no network, no writes.

set -euo pipefail

fail() { echo "SL08_VERIFY: FAIL — $1 (fail-closed)" >&2; exit 1; }

[ $# -ge 2 ] || { echo "usage: verify_b_artifact.sh <manifest> <expected-build-sha> [<artifact-root>]" >&2; exit 2; }

manifest="$1"
expected_build_sha="$2"
root="${3:-.}"

[ -f "$manifest" ] || fail "manifest missing: $manifest"
[ -d "$root" ] || fail "artifact root is not a directory: $root"

printf '%s' "$expected_build_sha" | grep -qE '^[0-9a-f]{40}$' \
  || fail "expected-build-sha '$expected_build_sha' is not a 40-hex OID"

# (a) build_sha == B — failed binding means the verifier is NOT base-built
# (Gate A violation: the PR would supply the verdict program).
actual_build_sha="$(awk -F' = ' '/^build_sha =/{print $2; exit}' "$manifest")"
[ -n "$actual_build_sha" ] || fail "manifest has no build_sha record"
[ "$actual_build_sha" = "$expected_build_sha" ] \
  || fail "manifest build_sha=$actual_build_sha != B=$expected_build_sha (verifier is NOT base-built — Gate A violation)"

# (b) per-file sha256 — same parse contract as the canonical workflow step:
# lines starting with 64-hex + 2 spaces are "sha256  path" entries.
count=0
while IFS=$'\t' read -r expect f; do
  count=$((count + 1))
  # Path containment: entries must be relative and stay inside the artifact
  # root (a manifest pointing outside the root is a broken binding).
  [[ "$f" = /* ]] && fail "absolute artifact path in manifest: $f"
  [[ "$f" =~ (^|/)\.\.(/|$) ]] && fail "artifact path escapes artifact root: $f"
  [ -f "$root/$f" ] || fail "artifact file missing: $f"
  actual="$(sha256sum "$root/$f" | awk '{print $1}')"
  [ "$actual" = "$expect" ] || fail "sha256 mismatch for $f (manifest=$expect actual=$actual)"
  echo "OK: $f (B-built)"
done < <(awk '/^[0-9a-f]{64}[[:space:]]{2}/{print $1 "\t" $2}' "$manifest")

# Vacuous-binding closure: a manifest with zero per-file entries must not pass
# (theater prohibition — an empty binding guarantees nothing).
[ "$count" -gt 0 ] || fail "manifest has no per-file sha256 entries (vacuous binding)"
echo "MANIFEST VERIFIED: verifier is built from B=$expected_build_sha"