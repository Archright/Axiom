#!/usr/bin/env bash
#
# verify_trusted_writer_set.sh — TrustedWriterSet equality gate (ADR-0022 §4,
# E2). Verifies that the set of repository workflows holding `contents: write`
# is EXACTLY the declared TrustedWriterSet (config/trusted_writer_set.json).
#
# TrustedWriterSet (ADR-0022 §4):
#   ALL workflows with contents:write  ⊆  TrustedWriterSet
#   TrustedWriterSet = { <trustedWriterWorkflow>@trustedAdmissionWorkflowSha }
# This script computes the observed set from .github/workflows/*.yml and
# asserts EXACT set equality (every observed member must be in the declared
# set AND every declared member must be observed) — a deviation in either
# direction fails (fail-closed).
#
# Parsing: .github/workflows/*.yml is scanned with a minimal line parser
# (grep/awk-style; yq/jq for the set file) — matching the publication_scope
# gate's hand-rolled parser philosophy. NO python. The `permissions:` block is
# the top-level block: a `contents: write` line under it marks the workflow as
# a trusted-writer candidate. The blob sha is derived with `git rev-parse
# HEAD:<workflow-path>` — never a worktree/pr-head file.
#
# Usage:
#   verify_trusted_writer_set.sh [--main-root <dir>] [--expect <count>]
#
# Exit codes:
#   0 — observed TrustedWriterSet == declared TrustedWriterSet (exact)
#   1 — mismatch (fail-closed; difference printed to stderr)
#   2 — usage/environment/configuration error (missing root, unparsable set
#       file, malformed entry, unknown argument — also fail-closed)
#
# Deterministic: same inputs → same verdict. No network, no writes.

set -euo pipefail

MAIN_ROOT=""
EXPECT_COUNT=""

usage() {
  echo "usage: verify_trusted_writer_set.sh [--main-root <dir>] [--expect <count>]" >&2
  exit 2
}

is_oid() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

while [ $# -gt 0 ]; do
  case "$1" in
    --main-root) MAIN_ROOT="${2:?--main-root requires a directory}"; shift 2 ;;
    --expect) EXPECT_COUNT="${2:?--expect requires a count}"; shift 2 ;;
    *) usage ;;
  esac
done

if [ -n "$MAIN_ROOT" ]; then
  [ -d "$MAIN_ROOT" ] || {
    echo "verify_trusted_writer_set: main root '$MAIN_ROOT' is not a directory" >&2
    exit 2
  }
  ROOT="$MAIN_ROOT"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi
cd "$ROOT"

[ -d .github/workflows ] || {
  echo "verify_trusted_writer_set: .github/workflows missing under $ROOT (configuration error — fail closed)" >&2
  exit 2
}

# ── 1. Declared TrustedWriterSet (config/trusted_writer_set.json). Full-line
# `//` documentation comments are stripped before jq parsing (same convention
# as config/executor_authority.json). Unparsable = configuration error (2).
SET_FILE="$ROOT/config/trusted_writer_set.json"
[ -f "$SET_FILE" ] || {
  echo "verify_trusted_writer_set: set file missing: $SET_FILE (configuration error — fail closed)" >&2
  exit 2
}
STRIPPED="$(sed -E 's|^[[:space:]]*//.*$||' "$SET_FILE")"
if ! DECL_WF="$(printf '%s' "$STRIPPED" | jq -r '.trustedWriterWorkflow' 2>/dev/null)" \
   || ! DECL_SHA="$(printf '%s' "$STRIPPED" | jq -r '.trustedAdmissionWorkflowSha' 2>/dev/null)" \
   || [ -z "$DECL_WF" ] || [ -z "$DECL_SHA" ]; then
  echo "verify_trusted_writer_set: cannot parse TrustedWriterSet from $SET_FILE (configuration error — fail closed)" >&2
  exit 2
fi
is_oid "$DECL_SHA" || {
  echo "verify_trusted_writer_set: malformed trustedAdmissionWorkflowSha '$DECL_SHA' in $SET_FILE (configuration error)" >&2
  exit 2
}
# TrustedWriterWorkflow is declared, not hardcoded: any path is accepted as
# long as it is exactly what config/trusted_writer_set.json declares. The
# equality check below (observed ⊆ declared ∧ declared ⊆ observed) is the
# enforceable contract — a workflow file must be in the declared set to hold
# contents:write at all (ADR-0022 §4).
case "$DECL_WF" in
  .github/workflows/*.yml) : ;;
  *)
    echo "verify_trusted_writer_set: declared trustedWriterWorkflow '$DECL_WF' is not a .github/workflows/*.yml path (configuration error)" >&2
    exit 2
    ;;
esac

# ── 2. Observed set — every .github/workflows/*.yml whose top-level
# permissions block declares `contents: write`. The workflow file NAME must
# match the declared trusted writer path (`.github/workflows/<name>.yml`);
# the blob sha is git-resolved at HEAD (never a worktree file).
OBSERVED=""
while IFS= read -r WF; do
  # Minimal permissions-block scan: only the top-level permissions block
  # counts. awk collects between the first `permissions:` (column 0) and the
  # next column-0 key; a `contents: write` line inside marks the writer.
  if awk '
      /^permissions:/ { in_perms=1; next }
      in_perms && /^[a-zA-Z0-9_-]+:/ { in_perms=0 }
      in_perms && /^[[:space:]]+contents:[[:space:]]+write([[:space:]]*#.*)?$/ { found=1 }
      END { exit !found }
    ' "$WF"; then
    WF_NAME="$(basename "$WF")"
    OBSERVED="$OBSERVED $WF_NAME"
  fi
done < <(find .github/workflows -maxdepth 1 -name '*.yml' -type f | sort)

OBSERVED="${OBSERVED# }"

if [ -n "$EXPECT_COUNT" ]; then
  [[ "$EXPECT_COUNT" =~ ^[0-9]+$ ]] || {
    echo "verify_trusted_writer_set: --expect '$EXPECT_COUNT' is not a count" >&2
    exit 2
  }
  OBS_COUNT="$(printf '%s\n' "$OBSERVED" | grep -c . || true)"
  if [ "$OBS_COUNT" != "$EXPECT_COUNT" ]; then
    echo "verify_trusted_writer_set: expected $EXPECT_COUNT contents:write workflow(s), observed $OBS_COUNT:${OBSERVED:+ $OBSERVED}" >&2
    exit 2
  fi
fi

# ── 3. Exact equality check (⊆ ∧ ⊇) — TWO identities (plan v12, OQ4):
#   a) WRITER identity: the observed top-level contents:write holder must be
#      EXACTLY the declared trustedWriterWorkflow (single writer — the gate's
#      top-level scan is what the authoritative design relies on; job-level
#      write holders such as canonical-main accept are transport-only and
#      never count here, ADR-0022 §4).
#   b) ADMISSION identity: the declared trustedAdmissionWorkflowSha is the
#      blob sha of the ADMISSION workflow the single writer trusts
#      (admission-check.yml). Its HEAD blob must equal the declaration
#      (HEAD blob vs 선언 — 기존 방식 유지).
# A violation in either direction fails (fail-closed).
MISMATCH=0
if [ -n "$OBSERVED" ]; then
  for WF_NAME in $OBSERVED; do
    WF_REL=".github/workflows/$WF_NAME"
    if [ "$WF_REL" != "$DECL_WF" ]; then
      echo "verify_trusted_writer_set: VIOLATION — $WF_REL holds contents:write but is NOT the declared trusted writer $DECL_WF (ADR-0022 §4, single writer)" >&2
      MISMATCH=1
    else
      echo "verify_trusted_writer_set: OK — $WF_REL is the declared trusted writer"
    fi
  done
else
  echo "verify_trusted_writer_set: VIOLATION — no workflow holds contents:write but TrustedWriterSet declares writer $DECL_WF (exact equality broken)" >&2
  MISMATCH=1
fi

# ── 3b. Admission identity — the declared admission file's HEAD blob must
# equal trustedAdmissionWorkflowSha (기존 방식 유지: HEAD blob vs 선언).
# GHEC: admission_producer.yml (deleted in CI=0) → admission-check.yml.
ADMISSION_FILE=".github/workflows/admission-check.yml"
ADM_BLOB="$(git rev-parse "HEAD:$ADMISSION_FILE" 2>/dev/null || true)"
if [ "$DECL_SHA" != "$ADM_BLOB" ]; then
  echo "verify_trusted_writer_set: VIOLATION — $ADMISSION_FILE HEAD blob ${ADM_BLOB:-<missing>} != declared trustedAdmissionWorkflowSha $DECL_SHA (single-value, atomic update required)" >&2
  MISMATCH=1
else
  echo "verify_trusted_writer_set: OK — $ADMISSION_FILE@$ADM_BLOB == trustedAdmissionWorkflowSha"
fi

# Exact equality also requires the declared member to be OBSERVED (⊇).
BLOB_OBS=0
if [ -n "$OBSERVED" ] && printf '%s\n' "$OBSERVED" | grep -qxF "$(basename "$DECL_WF")"; then
  BLOB_OBS=1
fi
if [ "$BLOB_OBS" -ne 1 ]; then
  echo "verify_trusted_writer_set: VIOLATION — declared trusted writer $DECL_WF not observed with contents:write (exact equality broken)" >&2
  MISMATCH=1
fi

if [ "$MISMATCH" -ne 0 ]; then
  echo "verify_trusted_writer_set: FAIL (exact TrustedWriterSet equality violated — fail closed)" >&2
  exit 1
fi
echo "verify_trusted_writer_set: PASS — contents:write holders == TrustedWriterSet = { $DECL_WF@$DECL_SHA }"