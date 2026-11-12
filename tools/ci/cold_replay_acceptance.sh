#!/usr/bin/env bash
# tools/ci/cold_replay_acceptance.sh — cold-replay acceptance harness (OC slice).
#
# Proves PRODUCT-STATE isolation of a cold replay from the reference (main)
# worktree's runtime state — not merely "main files unchanged":
#
#   1. clean git worktree at a given commit (or a supplied existing worktree)
#      with a FRESH AXIOM_STATE_DIR / AXIOM_PROVE_VAULT_DIR inside it;
#   2. scope lock seeded from the repo (contract input) with recorded byte
#      equality (sha256);
#   3. for EVERY --target in a comma-separated list, `ax prove --target <t>`
#      executed under `strace -f -y -e trace=openat`, sequentially, proving
#      into the SAME fresh state/vault dirs (one shared journal); per-target
#      traces are concatenated into trace_cold_prove.txt /
#      trace_warm_prove.txt so trace aggregation is unchanged, and
#      `ax report --json` runs ONCE per phase after the loop — one report
#      already sees all targets' journal claims (cold run, then warm rerun on
#      the same state for the warm/cold projection comparison);
#   4. assertions:
#        a. main runtime state (data/trusted/**, logs/**, .axiom/** — tracked
#           AND untracked) byte-identical before/after (sha256 manifest);
#           transient .axiom/cache/nimcache_leases/** churn (concurrent host
#           compile leases) is excluded from the manifest — any traced openat
#           of these paths remains a HARD isolation violation;
#           drifted paths correlated against the traces: a drifted path the
#           traced runs opened = contamination (FAIL); a drifted path outside
#           every traced open = concurrent external host activity → the
#           assertion is not decidable in that window → UNKNOWN;
#        b. zero openat of main runtime state in every trace (allow-list:
#           data/verification_scope.lock — tracked contract input;
#           src/verification/certificates/** — documented reference store,
#           proof_hydration.nim DEBT#433; main/.git/** recorded as expected
#           worktree backpointer, not runtime state);
#        c. cold worktree creates its own journal / vault / state artifacts;
#        d. warm vs cold: prove exit code, report exit code, volatile-stripped
#           report projection and `ax report --canonical-digest` all equal
#           (volatile keys mirror src/core/utils/canonical_projection.nim —
#           the SSOT list is not re-derived, only mirrored for the raw-file
#           diff; the digest itself is computed by the product);
#        e. subject identity in the cold journal is bound to the cold worktree:
#           zero occurrences of the main root path in cold artifacts, and every
#           journal claim modulePath resolves to a file under the cold root;
#        f. multi-target acceptance (EVALUATED PER PHASE): `ax report`
#           metrics.vkd equals {verified: <#targets>, total: <vksTotal from
#           the seeded scope lock>} — for the default list that is
#           {"verified":2,"total":23}; the journal carries one full-cert
#           claim symbol per target with DISTINCT symbols and DISTINCT
#           identityDigests, each status=certGreen with
#           verificationTier=dual-verified (dual SMT+Lean, tierToCertStatus
#           vtDual); and each claim's vault certificate binds back via
#           trustCommitId == the journal commit id (cert_writer.nim stamps
#           trustCommitId from commitCertificateVerification).
#   5. detector negative control: the trace analyzer MUST flag a deliberate
#      read of a main runtime FILE (an existing one, or a probe planted under
#      logs/** when the reference worktree has no runtime file — a bare
#      directory open is not a hard-path prefix match and blinds the control);
#      a detector that cannot see a planted access makes every PASS vacuous
#      → UNKNOWN.
#
# Journal claims are parsed in BOTH shapes: v1 flat certificate claims
# (modulePath/functionName/status/verificationTier/identityDigest at top
# level — what `ax prove` writes through commitCertificateVerification) and
# v2 compact `entries[]` checkpoints; the admission predicate mirrored here
# is cert_reconcile.isFullCertClaim.
#
# Per-target prove exit codes are aggregated to the phase worst: a timeout or
# crash (exit ∉ {0,1}) names its target in the UNKNOWN reason and is never
# interpreted as an isolation result.
#
# R3 INC-R3-001 gate (HARD): the wp5 negative control failed 4x (exit 4) and
# relocation invariance (pathIndependentProjectionEqual /
# subjectRunProjectionHashEqual in data/readiness/evidence/R3.json) remains
# UNKNOWN. Until both keys are present as JSON-bool `true` and unexpired, this
# harness NEVER emits PASS — it emits UNKNOWN (exit 3) even when every local
# assertion above holds. No false PASS is possible by construction.
#
# Exit codes (wp5_relocation_measure.nim convention):
#   0 = PASS (only reachable when the R3 gate is resolved)
#   2 = CLI misuse
#   3 = UNKNOWN (R3 INC-R3-001 unresolved, detector control failed, prove
#       timeout/crash, or infrastructure absence — fail-closed, no evidence
#       minted as PASS)
#   4 = FAIL (isolation violated: main runtime drift or main runtime openat;
#       OR a multi-target acceptance assertion (4f) is false)
#
# Usage:
#   cold_replay_acceptance.sh [--main-root DIR] [--commit SHA]
#                             [--cold-worktree DIR]
#                             [--target SYMBOL[,SYMBOL…]]
#                             [--out EVIDENCE.json] [--ax-bin PATH]
#                             [--r3-evidence PATH] [--prove-timeout SEC]
#                             [--clean]
#
# Defaults: --main-root = git toplevel of CWD; --commit = HEAD of main-root;
# --target = proximityScore,normalizeMaxWorkers; --out =
# <workdir>/cold_replay_evidence.json.
#
# --target accepts a comma-separated list. Elements are trimmed; empty
# elements and duplicates are rejected (exit 2). Canonical form is the
# qualified `module::function` (exact match against the frontier,
# src/cli/frontier_selection.nim); a bare name is accepted as the documented
# legacy substring form with a warning.
#
# Build bootstrap: a fresh worktree has no bin/ax (untracked build output).
# The harness reuses a coherent bin/ax when present (version handshake passes)
# and otherwise runs the documented bootstrap:
#   nim c --hints:off -o:bin/hermetic_build tools/hermetic_build.nim
#   bin/hermetic_build && make build
# (bin/hermetic_build regenerates the untracked src/generated/build_env.nim;
#  `make build` may also refresh stale tracked generated metadata — this drift
#  is confined to the cold worktree and is recorded in the evidence envelope.)

set -u -o pipefail

# ── CLI ──────────────────────────────────────────────────────────────────────
MAIN_ROOT="" ; COMMIT="" ; COLD_WT="" ; TARGET_SPEC="proximityScore,normalizeMaxWorkers" ; OUT=""
AX_BIN_OVERRIDE="" ; R3_EVIDENCE="" ; PROVE_TIMEOUT=600 ; CLEAN_AFTER=0

usage() { sed -n '2,102p' "$0" | grep -E '^#( |$)' | sed 's/^# \{0,1\}//'; exit 2; }
die() { printf '[cold_replay] %s\n' "$*" >&2; exit 3; }
die_misuse() { printf '[cold_replay] %s\n' "$*" >&2; exit 2; }
log() { printf '[cold_replay] %s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --main-root) [ $# -ge 2 ] || die_misuse "missing value for $1"; MAIN_ROOT="$2"; shift 2 ;;
    --commit) [ $# -ge 2 ] || die_misuse "missing value for $1"; COMMIT="$2"; shift 2 ;;
    --cold-worktree) [ $# -ge 2 ] || die_misuse "missing value for $1"; COLD_WT="$2"; shift 2 ;;
    --target) [ $# -ge 2 ] || die_misuse "missing value for $1"; TARGET_SPEC="$2"; shift 2 ;;
    --out) [ $# -ge 2 ] || die_misuse "missing value for $1"; OUT="$2"; shift 2 ;;
    --ax-bin) [ $# -ge 2 ] || die_misuse "missing value for $1"; AX_BIN_OVERRIDE="$2"; shift 2 ;;
    --r3-evidence) [ $# -ge 2 ] || die_misuse "missing value for $1"; R3_EVIDENCE="$2"; shift 2 ;;
    --prove-timeout) [ $# -ge 2 ] || die_misuse "missing value for $1"; PROVE_TIMEOUT="$2"; shift 2 ;;
    --clean) CLEAN_AFTER=1; shift ;;
    --help|-h) usage ;;
    *) die_misuse "unknown option: $1 (see --help)" ;;
  esac
done

# --target list: split on ',', trim each element, reject empty elements and
# duplicates. Canonical form is the qualified `module::function` (exact
# match, src/cli/frontier_selection.nim); a bare name is the documented
# legacy substring form — accepted with a warning, never silently.
# `read -a` drops a trailing empty field, so empty elements (leading/trailing
# comma, ',,') are rejected on the RAW spec first.
case ",$TARGET_SPEC," in
  *,,*) die_misuse "--target: empty target element in '$TARGET_SPEC'" ;;
esac
TARGETS=()
declare -A TARGET_SEEN=()
IFS=',' read -r -a TARGET_RAW <<< "$TARGET_SPEC"
for t in "${TARGET_RAW[@]}"; do
  t="${t#"${t%%[![:space:]]*}"}"; t="${t%"${t##*[![:space:]]}"}"   # trim
  [ -n "$t" ] || die_misuse "--target: empty target element in '$TARGET_SPEC'"
  if [ -n "${TARGET_SEEN[$t]+x}" ]; then
    die_misuse "--target: duplicate target '$t' in '$TARGET_SPEC'"
  fi
  TARGET_SEEN[$t]=1
  case "$t" in
    *::*)
      case "$t" in
        ::*|*::|*::**::*) die_misuse "--target: malformed qualified target '$t' (canonical form: module::function, non-empty halves, single '::')" ;;
        *) : ;;
      esac ;;
    *) log "warning: --target '$t' is a legacy bare name (substring match); canonical form is module::function" ;;
  esac
  TARGETS+=("$t")
done
[ "${#TARGETS[@]}" -gt 0 ] || die_misuse "--target: at least one target is required"
N_TARGETS=${#TARGETS[@]}

for t in git strace jq sha256sum timeout python3 nim make lake; do
  command -v "$t" >/dev/null 2>&1 || die "required tool not found on PATH: $t"
done
strace_bin="$(command -v strace)"

# ── reference (main) worktree identity ──────────────────────────────────────
if [ -z "$MAIN_ROOT" ]; then
  MAIN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
    || die "CWD is not inside a git worktree; pass --main-root"
fi
MAIN_ROOT="$(cd "$MAIN_ROOT" && pwd)" || die "main root not a directory: $MAIN_ROOT"
[ -f "$MAIN_ROOT/.axiom_root" ] || die "not an Axiom worktree (no .axiom_root): $MAIN_ROOT"
MAIN_HEAD_BEFORE="$(git -C "$MAIN_ROOT" rev-parse HEAD)" || die "git rev-parse failed in main root"

TS="$(date -u +%Y%m%dT%H%M%SZ)"
WORKDIR="${TMPDIR:-/tmp}/axiom_cold_replay_${TS}_$$"
mkdir -p "$WORKDIR" || die "cannot create workdir $WORKDIR"
[ -n "$OUT" ] || OUT="$WORKDIR/cold_replay_evidence.json"
mkdir -p "$(dirname "$OUT")" || die "cannot create evidence output dir: $(dirname "$OUT")"

log "main-root=$MAIN_ROOT head=${MAIN_HEAD_BEFORE:0:12}"
log "workdir=$WORKDIR"

# ── main runtime-state snapshot (tracked + untracked) ────────────────────────
# Watched runtime state per productization contract: data/trusted/** (tracked
# seeds + runtime journal), logs/** and .axiom/** (untracked runtime).
snapshot_main_runtime() {
  local out_file="$1"
  : > "$out_file"
  local rel
  for rel in data/trusted logs .axiom; do
    if [ -d "$MAIN_ROOT/$rel" ]; then
      ( cd "$MAIN_ROOT" && find "$rel" -type f -print0 ) \
        | sort -z \
        | while IFS= read -r -d '' f; do
            case "$f" in
              .axiom/cache/nimcache_leases|".axiom/cache/nimcache_leases/"*)
                # transient compile-lease churn: concurrent host nim processes
                # create/remove <pid> lease files inside the cold window; not
                # replay-target runtime state. Any traced openat of these
                # paths is still a HARD isolation violation (assertion 4b).
                continue ;;
            esac
            printf '%s\t%s\n' "$f" "$(sha256sum "$MAIN_ROOT/$f" | cut -d' ' -f1)"
          done >> "$out_file"
    fi
  done
  sort "$out_file" -o "$out_file"
}
snapshot_main_runtime "$WORKDIR/main_runtime_before.txt"
MAIN_FILES_BEFORE=$(wc -l < "$WORKDIR/main_runtime_before.txt")
log "main runtime snapshot: $MAIN_FILES_BEFORE files"

# ── cold worktree ────────────────────────────────────────────────────────────
CREATED_WT=0
if [ -z "$COLD_WT" ]; then
  if [ -z "$COMMIT" ]; then COMMIT="$MAIN_HEAD_BEFORE"; fi
  COLD_WT="${TMPDIR:-/tmp}/axiom_cold_wt_${TS}_$$"
  git -C "$MAIN_ROOT" worktree add --detach "$COLD_WT" "$COMMIT" >/dev/null 2>&1 \
    || die "git worktree add failed at $COLD_WT (commit=$COMMIT)"
  CREATED_WT=1
  log "created cold worktree at commit ${COMMIT:0:12}: $COLD_WT"
else
  COLD_WT="$(cd "$COLD_WT" && pwd)" || die "cold worktree not a directory: $COLD_WT"
  git -C "$COLD_WT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "--cold-worktree is not a git worktree: $COLD_WT"
  [ -z "$COMMIT" ] || die_misuse "--commit and --cold-worktree are mutually exclusive"
  log "reusing cold worktree: $COLD_WT ($(git -C "$COLD_WT" rev-parse HEAD | cut -c1-12))"
fi
COLD_HEAD="$(git -C "$COLD_WT" rev-parse HEAD)"

# ── fresh state dirs INSIDE the cold worktree ────────────────────────────────
STATE_DIR="$COLD_WT/build/cold_replay_state"
VAULT_DIR="$COLD_WT/build/cold_replay_vault"
rm -rf "$STATE_DIR" "$VAULT_DIR"
mkdir -p "$STATE_DIR/data" "$VAULT_DIR" || die "cannot create fresh state dirs"

# ── scope lock seed (contract input) + byte equality record ─────────────────
SCOPE_LOCK_SRC="$COLD_WT/data/verification_scope.lock"
SCOPE_LOCK_SEED="$STATE_DIR/data/verification_scope.lock"
[ -f "$SCOPE_LOCK_SRC" ] || die "scope lock missing in cold worktree: $SCOPE_LOCK_SRC"
cp "$SCOPE_LOCK_SRC" "$SCOPE_LOCK_SEED" || die "scope lock seed copy failed"
SCOPE_LOCK_SHA_SRC="$(sha256sum "$SCOPE_LOCK_SRC" | cut -d' ' -f1)"
SCOPE_LOCK_SHA_SEED="$(sha256sum "$SCOPE_LOCK_SEED" | cut -d' ' -f1)"
SCOPE_LOCK_BYTES_EQUAL=0
[ "$SCOPE_LOCK_SHA_SRC" = "$SCOPE_LOCK_SHA_SEED" ] && SCOPE_LOCK_BYTES_EQUAL=1
log "scope lock seeded sha256=${SCOPE_LOCK_SHA_SRC:0:12} bytesEqual=$SCOPE_LOCK_BYTES_EQUAL"

# ── cold runtime baseline (what exists BEFORE the runs) ─────────────────────
# The journal authority follows AXIOM_STATE_DIR (`activeJournalRoot`): the cold
# run relocates state into the cold worktree, so new journal records land under
# STATE_DIR, not the checkout's data/trusted/journal.
JOURNAL_DIR="$STATE_DIR/data/trusted/journal"
JOURNAL_BEFORE=0
[ -d "$JOURNAL_DIR" ] && JOURNAL_BEFORE=$(find "$JOURNAL_DIR" -name '*.json' -type f | wc -l)

# ── binary bootstrap (bin/ax is untracked — a fresh worktree has none) ──────
bootstrap_bin() {
  if [ -n "$AX_BIN_OVERRIDE" ]; then
    [ -x "$AX_BIN_OVERRIDE" ] || die "--ax-bin not executable: $AX_BIN_OVERRIDE"
    printf '%s' "$AX_BIN_OVERRIDE"
    return 0
  fi
  if [ -x "$COLD_WT/bin/ax" ] \
     && (cd "$COLD_WT" && timeout 60 ./bin/ax --version >/dev/null 2>&1); then
    printf '%s' "$COLD_WT/bin/ax"
    return 0
  fi
  log "bootstrapping bin/ax + ircheck in cold worktree (nim c hermetic_build && hermetic_build && make build && lake build ircheck)…"
  ( cd "$COLD_WT" \
    && nim c --hints:off -o:bin/hermetic_build tools/hermetic_build.nim \
    && ./bin/hermetic_build \
    && make build \
    && ( cd proofs && lake build ircheck ) ) > "$WORKDIR/build.log" 2>&1 \
    || { tail -20 "$WORKDIR/build.log" >&2; die "cold worktree build failed (see $WORKDIR/build.log)"; }
  printf '%s' "$COLD_WT/bin/ax"
}
AX_BIN="$(bootstrap_bin)" || exit 3
[ -x "$AX_BIN" ] || die "bootstrapped ax binary not executable: $AX_BIN"
log "ax binary: $AX_BIN ($(cd "$COLD_WT" && "$AX_BIN" --version 2>/dev/null | head -1))"

# ── traced execution helpers ─────────────────────────────────────────────────
# Env scrub: every AXIOM_* variable that can redirect state/roots/vault is
# unset before the run; only AXIOM_STATE_DIR / AXIOM_PROVE_VAULT_DIR are set,
# both pointing INSIDE the cold worktree (src/core/trusted/env_types.nim).
SCRUB_ENV=(env -u AXIOM_STATE_DIR -u AXIOM_STATE_PATH -u AXIOM_STATE_LEDGER_PATH
  -u AXIOM_PROVE_VAULT_DIR -u AXIOM_VAULT_DIR -u AXIOM_LOG_DIR
  -u AXIOM_ROOT -u AXIOM_REPO_ROOT -u AXIOM_PROVE_BINARY
  -u AXIOM_PROOF_CACHE_PATH -u AXIOM_LEAN_CMD
  "AXIOM_STATE_DIR=$STATE_DIR" "AXIOM_PROVE_VAULT_DIR=$VAULT_DIR")

traced_run() {  # traced_run <trace-out> <timeout-sec> <cmd…>
  local trace="$1" tmo="$2"; shift 2
  ( cd "$COLD_WT" && "${SCRUB_ENV[@]}" "$strace_bin" -f -y -e trace=openat \
      -o "$trace" timeout "$tmo" "$@" )
}

canonical_digest() {  # canonical_digest <state-file> <trace-out> → echoes digest
  local sf="$1" trace="$2"
  [ -f "$sf" ] || return 1
  ( cd "$COLD_WT" && "${SCRUB_ENV[@]}" "$strace_bin" -f -y -e trace=openat \
      -o "$trace" timeout 120 "$AX_BIN" report \
      --canonical-digest --state-file "$sf" 2>/dev/null ) | \
    grep -E '^[0-9a-f]{64}$' | tail -1
}

emit_unknown() {  # emit_unknown <reason> — infrastructure-absence record, exit 3
  log "verdict=UNKNOWN exit=3 ($1)"
  jq -n --arg reason "$1" '{verdict:"UNKNOWN", exitCode:3, reason:$reason}' > "$OUT"
  exit 3
}

worst_exit() {  # worst_exit <exit…> → numerically worst (max)
  local w=0 e
  for e in "$@"; do [ "$e" -gt "$w" ] && w="$e"; done
  printf '%s' "$w"
}

# Per-target worst-exit aggregation. A prove exit outside {0,1} is a crash or
# a timeout (124) — recorded against the NAMED target, never interpreted as
# an isolation verdict. The loop CONTINUES to the remaining targets so their
# evidence still lands in the shared journal; verdict aggregation turns any
# bad exit into UNKNOWN naming every failed target.
PROVE_FAIL_TARGETS=()
run_prove_phase() {  # run_prove_phase <phase-label> <prefix> <exits-array-name>
  local phase_label="$1" prefix="$2" exits_var="$3"
  local i t rc kind
  for i in "${!TARGETS[@]}"; do
    t="${TARGETS[$i]}"
    log "$phase_label [$((i+1))/$N_TARGETS]: ax prove --target $t (traced)…"
    traced_run "$WORKDIR/trace_${prefix}_prove_$i.txt" "$PROVE_TIMEOUT" \
      "$AX_BIN" prove --target "$t" > "$WORKDIR/${prefix}_prove_$i.out" 2>&1
    rc=$?
    local -n exits="$exits_var"
    exits+=("$rc")
    log "$prefix prove target=$t exit=$rc"
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
      kind="crashed"
      [ "$rc" -eq 124 ] && kind="timed out (deadline ${PROVE_TIMEOUT}s)"
      PROVE_FAIL_TARGETS+=("$prefix phase target '$t': exit $rc — $kind")
    fi
  done
  # Concatenate the per-target traces into the single canonical phase trace
  # so PYANALYZE/PYDRIFT and the evidence samples keep the original names.
  cat "$WORKDIR"/trace_${prefix}_prove_*.txt > "$WORKDIR/trace_${prefix}_prove.txt"
}

# ── COLD phase (fresh state — every target proves into the SAME dirs) ────────
COLD_PROVE_EXITS=()
COLD_T0=$(date +%s)
run_prove_phase "COLD run" "cold" COLD_PROVE_EXITS
COLD_PROVE_SEC=$(( $(date +%s) - COLD_T0 ))
COLD_PROVE_EXIT="$(worst_exit "${COLD_PROVE_EXITS[@]}")"
log "cold prove done (${COLD_PROVE_SEC}s): per-target exits [${COLD_PROVE_EXITS[*]}] worst=$COLD_PROVE_EXIT"

log "COLD run: ax report --json (traced; one report sees all $N_TARGETS targets' journal claims)…"
traced_run "$WORKDIR/trace_cold_report.txt" 120 \
  "$AX_BIN" report --json > "$WORKDIR/cold_report.json" 2>"$WORKDIR/cold_report.err"
COLD_REPORT_EXIT=$?
COLD_STATE_FILE="$STATE_DIR/logs/ax_proof_state.json"
if [ ! -f "$COLD_STATE_FILE" ]; then
  REASON="cold canonical digest unavailable — no state file at $COLD_STATE_FILE"
  [ "${#PROVE_FAIL_TARGETS[@]}" -gt 0 ] && REASON+="; prove failures: ${PROVE_FAIL_TARGETS[*]}"
  emit_unknown "$REASON"
fi
COLD_DIGEST="$(canonical_digest "$COLD_STATE_FILE" "$WORKDIR/trace_cold_digest.txt")" || COLD_DIGEST=""
[ -n "$COLD_DIGEST" ] || emit_unknown "cold canonical digest unavailable (state file: $COLD_STATE_FILE)"
log "cold canonical digest=${COLD_DIGEST:0:12}"

# ── WARM phase (same state dirs — cache boundary; same target order) ─────────
WARM_PROVE_EXITS=()
run_prove_phase "WARM run" "warm" WARM_PROVE_EXITS
WARM_PROVE_EXIT="$(worst_exit "${WARM_PROVE_EXITS[@]}")"
log "warm prove done: per-target exits [${WARM_PROVE_EXITS[*]}] worst=$WARM_PROVE_EXIT"
traced_run "$WORKDIR/trace_warm_report.txt" 120 \
  "$AX_BIN" report --json > "$WORKDIR/warm_report.json" 2>"$WORKDIR/warm_report.err"
WARM_REPORT_EXIT=$?
WARM_DIGEST="$(canonical_digest "$COLD_STATE_FILE" "$WORKDIR/trace_warm_digest.txt")" || WARM_DIGEST=""
[ -n "$WARM_DIGEST" ] || emit_unknown "warm canonical digest unavailable"


# ── detector negative control (must-flag) ────────────────────────────────────
# Plant a deliberate read of a main runtime FILE; the analyzer MUST classify it
# as a hard main-runtime hit. A blind analyzer invalidates every PASS. The
# control target must be a FILE under a hard runtime prefix (logs/**,
# data/trusted/**, .axiom/**): a bare directory open (e.g. `.axiom`) is not a
# hard-path prefix match and would silently blind the negative control. A
# planted probe is created AND removed inside the snapshot window, so it cannot
# register as main runtime drift.
CTRL_FILE="" ; CTRL_PLANTED=0 ; CTRL_PROBE="$MAIN_ROOT/logs/.cold_replay_probe.$$"
CTRL_CANDS=("$MAIN_ROOT/logs/ax_proof_state.json")
for ctrl_root in "$MAIN_ROOT/logs" "$MAIN_ROOT/data/trusted" "$MAIN_ROOT/.axiom"; do
  while IFS= read -r f; do CTRL_CANDS+=("$f"); done < <(find "$ctrl_root" -type f 2>/dev/null | head -8)
done
for cand in "${CTRL_CANDS[@]}"; do
  [ -f "$cand" ] && { CTRL_FILE="$cand"; break; }
done
if [ -z "$CTRL_FILE" ] \
   && mkdir -p "$MAIN_ROOT/logs" 2>/dev/null \
   && printf 'axiom cold-replay detector negative control probe\n' > "$CTRL_PROBE" 2>/dev/null; then
  CTRL_FILE="$CTRL_PROBE" ; CTRL_PLANTED=1
fi
if [ -z "$CTRL_FILE" ]; then
  log "detector control: no main runtime file available to plant — UNKNOWN"
  DETECTOR_CONTROL="absent-no-plantable-file"
else
  strace -f -y -e trace=openat -o "$WORKDIR/trace_detector_control.txt" \
    cat "$CTRL_FILE" >/dev/null 2>&1
  if [ "$CTRL_PLANTED" -eq 1 ]; then
    rm -f "$CTRL_PROBE"
    rmdir "$MAIN_ROOT/logs" 2>/dev/null || true
  fi
  DETECTOR_CONTROL="pending-analysis"
fi

# ── trace analysis ───────────────────────────────────────────────────────────
# Classification (paths under the MAIN root):
#   hard      — data/trusted/**, logs/**, .axiom/**  (runtime state; any hit = FAIL)
#   allowed   — data/verification_scope.lock, src/verification/certificates/**
#   expected  — .git/** (worktree backpointer: .git file points at the common dir)
#   other     — any other main-root path (recorded; not runtime state)
python3 - "$WORKDIR" "$MAIN_ROOT" <<'PYANALYZE'
import json, re, sys, os

workdir, main_root = sys.argv[1], sys.argv[2]
p = main_root.rstrip("/") + "/"
HARD = (p + "data/trusted/", p + "logs/", p + ".axiom/")
ALLOWED = (p + "data/verification_scope.lock", p + "src/verification/certificates/")
EXPECTED = (p + ".git/",)

line_re = re.compile(r"openat\(")
str_re = re.compile(r'"([^"]*)"')
res_re = re.compile(r"=\s*(-?\d+)(?:<([^>]*)>)?\s*$")

OCTAL = re.compile(r"\\([0-7]{3})")
def unescape(s):
    # strace -y renders non-ASCII path bytes as \NNN octal escapes (e.g. the
    # UTF-8 of <home-desktop>). Decode octal triplets to bytes, then UTF-8 decode.
    if "\\" not in s:
        return s
    out = bytearray()
    i = 0
    while i < len(s):
        m = OCTAL.match(s, i)
        if m:
            out.append(int(m.group(1), 8))
            i = m.end()
        else:
            out.extend(s[i].encode("utf-8"))
            i += 1
    return out.decode("utf-8", errors="replace")

def classify(path):
    if path.startswith(HARD): return "hard"
    if path.startswith(ALLOWED): return "allowed"
    if path.startswith(EXPECTED): return "expected"
    if path.startswith(p): return "other"
    return None

def analyze(trace_path):
    hits = {"hard": set(), "allowed": set(), "expected": set(), "other": set()}
    n = 0
    if not os.path.exists(trace_path):
        return {"total_openat": 0, "hits": {k: sorted(v) for k, v in hits.items()}, "exists": False}
    with open(trace_path, errors="replace") as fh:
        for line in fh:
            if "openat(" not in line:
                continue
            n += 1
            body = line.split("openat(", 1)[1]
            strs = [unescape(s) for s in str_re.findall(body)]
            res = res_re.search(body.strip())
            cands = []
            # pathname arg candidates: any absolute quoted token (dirfd is
            # AT_FDCWD or an integer, never quoted-absolute)
            for s in strs:
                if s.startswith("/"):
                    cands.append(s)
            if res and res.group(2) and res.group(2).startswith("/"):
                cands.append(unescape(res.group(2)))  # -y resolved path: authority
            for c in cands:
                cat = classify(c)
                if cat:
                    hits[cat].add(c)
    return {"total_openat": n, "exists": True,
            "hits": {k: sorted(v) for k, v in hits.items()}}

out = {}
for name in ["cold_prove", "cold_report", "cold_digest",
             "warm_prove", "warm_report", "warm_digest"]:
    out[name] = analyze(os.path.join(workdir, f"trace_{name}.txt"))
# detector control: hard-category hit MUST exist
ctrl = analyze(os.path.join(workdir, "trace_detector_control.txt"))
out["detector_control"] = ctrl
out["detector_control_planted"] = ctrl["hits"]["hard"]
with open(os.path.join(workdir, "trace_analysis.json"), "w") as fh:
    json.dump(out, fh, indent=1)
PYANALYZE
[ -f "$WORKDIR/trace_analysis.json" ] || die "trace analyzer produced no output"

DETECTOR_OK=0
if [ "$DETECTOR_CONTROL" = "absent-no-plantable-file" ]; then
  DETECTOR_OK=0
else
  DETECTOR_OK=$(jq -r '(.detector_control.hits.hard | length) > 0' "$WORKDIR/trace_analysis.json")
fi
log "detector control (planted main read must be flagged): detected=$DETECTOR_OK"

# ── post-run main runtime snapshot + drift ───────────────────────────────────
snapshot_main_runtime "$WORKDIR/main_runtime_after.txt"
MAIN_DRIFT="$(diff "$WORKDIR/main_runtime_before.txt" "$WORKDIR/main_runtime_after.txt" || true)"
MAIN_HEAD_AFTER="$(git -C "$MAIN_ROOT" rev-parse HEAD)"
if [ -n "$MAIN_DRIFT" ]; then
  printf '%s\n' "$MAIN_DRIFT" > "$WORKDIR/main_runtime_drift.txt"
  log "main runtime state drifted during run — attributing against traces…"
else
  : > "$WORKDIR/main_runtime_drift.txt"
fi

# Drift attribution: a drifted path that appears among the traced openat paths
# is attributable to the harness's own runs (contamination → FAIL). A drifted
# path outside every traced open is concurrent EXTERNAL activity on the shared
# host — the byte-identity assertion cannot be validated in a noisy window →
# UNKNOWN (fail-closed), never a silent PASS and never a misattributed FAIL.
python3 - "$WORKDIR" "$MAIN_ROOT" <<'PYDRIFT'
import json, os, sys

workdir, main_root = sys.argv[1], sys.argv[2]
drift_paths = set()
drift_file = os.path.join(workdir, "main_runtime_drift.txt")
if os.path.exists(drift_file):
    for line in open(drift_file, errors="replace"):
        if line[:1] in "<>":
            parts = line[2:].strip().rsplit("\t", 1)
            if parts and parts[0]:
                drift_paths.add(parts[0])

analysis = json.load(open(os.path.join(workdir, "trace_analysis.json")))
traced = set()
# Attribution set = the REPLAY RUN traces only. The detector control
# deliberately opens a main runtime file — it must NOT feed drift
# attribution, or its planted path would falsely claim a coincidental
# external drift of the same file.
for name in ["cold_prove", "cold_report", "cold_digest",
             "warm_prove", "warm_report", "warm_digest"]:
    entry = analysis.get(name, {})
    if not isinstance(entry, dict) or "hits" not in entry:
        continue
    for cat, paths in entry["hits"].items():
        traced.update(paths)

res = {"drifted": sorted(drift_paths), "harness_attributable": [],
       "external": []}
for dp in sorted(drift_paths):
    if os.path.join(main_root, dp) in traced:
        res["harness_attributable"].append(dp)
    else:
        res["external"].append(dp)
with open(os.path.join(workdir, "drift_classified.json"), "w") as fh:
    json.dump(res, fh, indent=1)
PYDRIFT
[ -f "$WORKDIR/drift_classified.json" ] || die "drift classifier produced no output"

# ── cold-created artifacts + journal subject binding ─────────────────────────
JOURNAL_AFTER=0
[ -d "$JOURNAL_DIR" ] && JOURNAL_AFTER=$(find "$JOURNAL_DIR" -name '*.json' -type f | wc -l)
JOURNAL_NEW=$(( JOURNAL_AFTER - JOURNAL_BEFORE ))
VAULT_CREATED=0
{ [ -f "$VAULT_DIR/manifest.json" ] || [ -n "$(ls -A "$VAULT_DIR" 2>/dev/null)" ]; } && VAULT_CREATED=1
STATE_CREATED=0
[ -f "$COLD_STATE_FILE" ] && STATE_CREATED=1

python3 - "$COLD_WT" "$MAIN_ROOT" "$JOURNAL_DIR" "$WORKDIR" "$JOURNAL_BEFORE" "$VAULT_DIR" <<'PYBIND'
import glob, json, os, sys

cold, main, journal, workdir, vault = (sys.argv[1], sys.argv[2], sys.argv[3],
                                       sys.argv[4], sys.argv[6])
before = int(sys.argv[5])

def parse_claim(rec):
    """Classify a journal record's claim payload.

    Shapes mirror cert_reconcile.isFullCertClaim / the v2 checkpoint format:
      v1_full_cert — flat certificate claim: modulePath/functionName/
                     sourceHash/irHash/toolchainIdentity/semanticProfileId at
                     TOP level (what `ax prove` writes through
                     commitCertificateVerification);
      v2_entries   — compact `entries[]` checkpoint (catalog, never admission);
      other        — anything else (recorded, not symbol-admissible)."""
    raw = rec.get("claim", "")
    if not isinstance(raw, str) or not raw.strip():
        return None, "empty"
    try:
        c = json.loads(raw)
    except Exception:
        return None, "unparseable"
    if not isinstance(c, dict):
        return None, "nonobject"
    if "entries" in c:
        return c, "v2_entries"
    if (c.get("modulePath") and c.get("functionName") and c.get("sourceHash")
            and c.get("irHash") and "toolchainIdentity" in c
            and c.get("semanticProfileId")):
        return c, "v1_full_cert"
    return c, "other"

files = sorted(glob.glob(os.path.join(journal, "*.json")))[before:]  # only new records
res = {"new_journal_records": len(files), "main_path_occurrences": [],
       "claims": [], "unresolved_module_paths": [], "symbols": {},
       "full_cert_claim_records": 0, "checked": True}

def unresolved(mp):
    if mp and not os.path.exists(os.path.join(cold, mp)):
        res["unresolved_module_paths"].append(mp)

def note_full_cert(commit_id, claim):
    res["full_cert_claim_records"] += 1
    mp = claim.get("modulePath", "")
    sym = mp + "::" + claim.get("functionName", "")
    s = res["symbols"].setdefault(sym, {
        "modulePath": mp, "function": claim.get("functionName", ""),
        "identityDigests": [], "statuses": [], "verificationTiers": [],
        "commitIds": [], "records": 0,
        "vaultCertFound": False, "trustCommitIdBound": False, "vaultCert": None})
    s["records"] += 1
    for key, val in (("identityDigests", claim.get("identityDigest", "")),
                     ("statuses", claim.get("status", "")),
                     ("verificationTiers", claim.get("verificationTier", ""))):
        if val and val not in s[key]:
            s[key].append(val)
    if commit_id and commit_id not in s["commitIds"]:
        s["commitIds"].append(commit_id)

# Vault certificates written by THIS run (fresh dir): identityDigest -> cert.
# trustCommitId was stamped by cert_writer.nim from
# commitCertificateVerification — it names the journal record whose claim is
# this certificate's pre-provenance content.
vault_certs = {}
for vp in sorted(glob.glob(os.path.join(vault, "*.json"))):
    try:
        cert = json.load(open(vp, errors="replace"))
    except Exception:
        continue
    if isinstance(cert, dict) and cert.get("identityDigest"):
        vault_certs[cert["identityDigest"]] = {
            "file": os.path.basename(vp),
            "trustCommitId": cert.get("trustCommitId", "")}

for f in files:
    name = os.path.basename(f)
    raw = open(f, errors="replace").read()
    if main in raw:
        res["main_path_occurrences"].append(name)
    commit_id = name[:-5] if name.endswith(".json") else name  # <commitId>.json
    try:
        rec = json.loads(raw)
        claim, shape = parse_claim(rec)
    except Exception as ex:
        res["claims"].append({"record": name, "error": str(ex)})
        continue
    if shape == "v1_full_cert":
        note_full_cert(commit_id, claim)
        res["claims"].append({
            "record": name, "commitId": commit_id, "shape": shape,
            "modulePath": claim.get("modulePath", ""),
            "function": claim.get("functionName", ""),
            "status": claim.get("status", ""),
            "verificationTier": claim.get("verificationTier", ""),
            "identityDigest": claim.get("identityDigest", "")})
        unresolved(claim.get("modulePath", ""))
    elif shape == "v2_entries":
        for e in claim.get("entries", []):
            mp = e.get("modulePath", "")
            res["claims"].append({"record": name, "commitId": commit_id,
                                  "shape": shape, "modulePath": mp,
                                  "function": e.get("functionName", ""),
                                  "status": e.get("status", "")})
            unresolved(mp)
    else:
        res["claims"].append({"record": name, "commitId": commit_id,
                              "shape": shape})
        if isinstance(claim, dict):
            unresolved(claim.get("modulePath", ""))

# Trust binding per symbol: a vault certificate whose identityDigest matches
# one of the symbol's journal claims AND whose trustCommitId names one of the
# journal records carrying that claim.
for sym, s in res["symbols"].items():
    for d in s["identityDigests"]:
        vc = vault_certs.get(d)
        if vc:
            s["vaultCertFound"] = True
            if vc["trustCommitId"] and vc["trustCommitId"] in s["commitIds"]:
                s["trustCommitIdBound"] = True
                s["vaultCert"] = vc

with open(os.path.join(workdir, "journal_binding.json"), "w") as fh:
    json.dump(res, fh, indent=1)
PYBIND
[ -f "$WORKDIR/journal_binding.json" ] || die "journal binding analyzer produced no output"

# ── warm vs cold comparison (volatile-stripped report projection) ────────────
# Volatile keys mirrored verbatim from src/core/utils/canonical_projection.nim
# volatileKeys (SSOT; the harness mirrors only for the raw-report diff — the
# authoritative projection equality is the product's --canonical-digest).
VOLATILE_KEYS="timestamp,startedAtMs,endedAtMs,elapsedMs,solverElapsedMs,parallelOverheadMs,activeNodeCount,availableMemoryBytes,cpuLoadRatio,recommendedWorkerCount,totalWallTimeMs,hotspotElapsedMs,hotspotLabel,runId,generatedAt,processId,timedOut,timeout,timeoutCount,timeoutNodes,timeoutImpactNodes,timeoutHotspots,timeoutComplexityWeight,wallElapsedMs,vaultPath,tmpPath,absolutePath,path,sourcePath,subjectRoot,stateRoot,repoRoot,cacheHit,cacheHitCount"
# jq walk+del with dynamic keys: build the del() expression from the mirrored list.
DEL_EXPR="$(printf '%s' "$VOLATILE_KEYS" | awk -F, '{out="del("; for(i=1;i<=NF;i++){out=out ((i>1)?",":"") "."$i} out=out ")"; print out}')"
strip_volatile() {
  jq -S "walk(if type == \"object\" then $DEL_EXPR else . end)" "$1" 2>/dev/null
}
strip_volatile "$WORKDIR/cold_report.json" > "$WORKDIR/cold_report_stripped.json"
strip_volatile "$WORKDIR/warm_report.json" > "$WORKDIR/warm_report_stripped.json"
# Validity guard: an unparseable/empty report must not silently compare equal.
REPORTS_VALID=true
jq -e . "$WORKDIR/cold_report.json" >/dev/null 2>&1 || REPORTS_VALID=false
jq -e . "$WORKDIR/warm_report.json" >/dev/null 2>&1 || REPORTS_VALID=false
[ -s "$WORKDIR/cold_report_stripped.json" ] || REPORTS_VALID=false
[ -s "$WORKDIR/warm_report_stripped.json" ] || REPORTS_VALID=false
if [ "$REPORTS_VALID" != "true" ]; then
  REASON="ax report did not emit a valid JSON document"
  [ "${#PROVE_FAIL_TARGETS[@]}" -gt 0 ] && REASON+="; prove failures: ${PROVE_FAIL_TARGETS[*]}"
  log "report output not valid JSON — UNKNOWN (fail-closed)"
  jq -n --arg reason "$REASON" '{verdict:"UNKNOWN", exitCode:3, reason:$reason}' > "$OUT"
  exit 3
fi
REPORT_PROJECTION_EQUAL=$(cmp -s "$WORKDIR/cold_report_stripped.json" "$WORKDIR/warm_report_stripped.json" && echo true || echo false)
DIGEST_EQUAL=$([ "$COLD_DIGEST" = "$WARM_DIGEST" ] && echo true || echo false)
PROVE_EXIT_EQUAL=$([ "$COLD_PROVE_EXIT" = "$WARM_PROVE_EXIT" ] && echo true || echo false)
REPORT_EXIT_EQUAL=$([ "$COLD_REPORT_EXIT" = "$WARM_REPORT_EXIT" ] && echo true || echo false)
log "warm/cold: digestEqual=$DIGEST_EQUAL reportProjectionEqual=$REPORT_PROJECTION_EQUAL proveExitEqual=$PROVE_EXIT_EQUAL reportExitEqual=$REPORT_EXIT_EQUAL"

# ── R3 INC-R3-001 gate ───────────────────────────────────────────────────────
# data/readiness/evidence/R3.json is the authority for relocation invariance.
# Both keys present as JSON-bool true AND unexpired → gate RESOLVED (PASS
# reachable). Otherwise the gate is UNKNOWN and this harness emits UNKNOWN.
R3_FILE="${R3_EVIDENCE:-$COLD_WT/data/readiness/evidence/R3.json}"
R3_RESOLVED=false ; R3_REASON=""
if [ ! -f "$R3_FILE" ]; then
  R3_REASON="R3 evidence file missing: $R3_FILE"
else
  R3_KEYS=$(jq -r \
    '[.observations[]? | select(.key=="pathIndependentProjectionEqual" or .key=="subjectRunProjectionHashEqual") | {key, value, isBoolTrue: (.value == true)}] ' \
    "$R3_FILE" 2>/dev/null)
  N_KEYS=$(printf '%s' "$R3_KEYS" | jq 'length')
  N_TRUE=$(printf '%s' "$R3_KEYS" | jq '[.[] | select(.isBoolTrue)] | length')
  FRESH_UNTIL=$(jq -r '.collection.freshUntil // ""' "$R3_FILE")
  NOW_EPOCH=$(date +%s)
  FRESH_EPOCH=$(date -d "$FRESH_UNTIL" +%s 2>/dev/null || echo 0)
  if [ "$N_KEYS" -ge 2 ] && [ "$N_TRUE" -eq "$N_KEYS" ] && [ "$FRESH_EPOCH" -ge "$NOW_EPOCH" ]; then
    R3_RESOLVED=true
  else
    R3_REASON="relocation keys present=$N_KEYS/2 bool-true=$N_TRUE/2 freshUntil='${FRESH_UNTIL:-<absent>}' — INC-R3-001 unresolved (wp5 negative control failed 4x, exit 4)"
  fi
fi
log "R3 gate resolved=$R3_RESOLVED ${R3_REASON:+($R3_REASON)}"

# ── trace assertion totals ───────────────────────────────────────────────────
HARD_HITS=$(jq -r \
  '[.cold_prove.hits.hard, .cold_report.hits.hard, .cold_digest.hits.hard,
    .warm_prove.hits.hard, .warm_report.hits.hard, .warm_digest.hits.hard] | flatten | length' \
  "$WORKDIR/trace_analysis.json")
ALLOWED_HITS=$(jq -r \
  '[.cold_prove.hits.allowed, .cold_report.hits.allowed, .cold_digest.hits.allowed,
    .warm_prove.hits.allowed, .warm_report.hits.allowed, .warm_digest.hits.allowed] | flatten | length' \
  "$WORKDIR/trace_analysis.json")
EXPECTED_HITS=$(jq -r \
  '[.cold_prove.hits.expected, .cold_report.hits.expected, .cold_digest.hits.expected,
    .warm_prove.hits.expected, .warm_report.hits.expected, .warm_digest.hits.expected] | flatten | length' \
  "$WORKDIR/trace_analysis.json")
OTHER_HITS=$(jq -r \
  '[.cold_prove.hits.other, .cold_report.hits.other, .cold_digest.hits.other,
    .warm_prove.hits.other, .warm_report.hits.other, .warm_digest.hits.other] | flatten | length' \
  "$WORKDIR/trace_analysis.json")
log "trace main-root hits: hard=$HARD_HITS allowed(contract-input)=$ALLOWED_HITS expected(.git)=$EXPECTED_HITS other=$OTHER_HITS"

# ── verdict aggregation (FAIL > UNKNOWN > PASS) ──────────────────────────────
VERDICT="UNKNOWN" ; EXIT_CODE=3 ; FAIL_REASONS=() ; UNKNOWN_REASONS=()

MAIN_PATH_OCC=$(jq -r '.main_path_occurrences | length' "$WORKDIR/journal_binding.json")
UNRESOLVED_MP=$(jq -r '.unresolved_module_paths | length' "$WORKDIR/journal_binding.json")
DRIFT_ATTR=$(jq -r '.harness_attributable | length' "$WORKDIR/drift_classified.json")
DRIFT_EXT=$(jq -r '.external | length' "$WORKDIR/drift_classified.json")
DRIFT_TOTAL=$(jq -r '.drifted | length' "$WORKDIR/drift_classified.json")
log "main runtime drift: total=$DRIFT_TOTAL harness-attributable=$DRIFT_ATTR external=$DRIFT_EXT"

# ── multi-target acceptance assertions (4f) ──────────────────────────────────
# Decidable acceptance evidence: violation = FAIL (the evidence shows the
# contract is not met — nothing UNKNOWN about it). VKD denominator mirrors
# proof_hydration.getCanonicalVkdMetrics: vksTotal, kernel_total fallback.
EXPECTED_TOTAL=$(jq -r 'if (.vksTotal // 0) > 0 then .vksTotal else (.kernel_total // 0) end' "$SCOPE_LOCK_SRC")
COLD_VKD_VERIFIED=$(jq -r '.metrics.vkd.verified // -1' "$WORKDIR/cold_report.json")
COLD_VKD_TOTAL=$(jq -r '.metrics.vkd.total // -1' "$WORKDIR/cold_report.json")
WARM_VKD_VERIFIED=$(jq -r '.metrics.vkd.verified // -1' "$WORKDIR/warm_report.json")
WARM_VKD_TOTAL=$(jq -r '.metrics.vkd.total // -1' "$WORKDIR/warm_report.json")
REPORT_COLD_VKD_OK=$([ "$COLD_VKD_VERIFIED" = "$N_TARGETS" ] && [ "$COLD_VKD_TOTAL" = "$EXPECTED_TOTAL" ] && echo true || echo false)
REPORT_WARM_VKD_OK=$([ "$WARM_VKD_VERIFIED" = "$N_TARGETS" ] && [ "$WARM_VKD_TOTAL" = "$EXPECTED_TOTAL" ] && echo true || echo false)
N_SYMBOLS=$(jq -r '.symbols | length' "$WORKDIR/journal_binding.json")
SYMBOLS_GREEN_DUAL=$(jq -r '[.symbols[] | .statuses == ["certGreen"] and .verificationTiers == ["dual-verified"]] | all' "$WORKDIR/journal_binding.json")
DIGEST_INSTANCES=$(jq -r '[.symbols[].identityDigests[]] | length' "$WORKDIR/journal_binding.json")
DIGEST_UNIQUE=$(jq -r '[.symbols[].identityDigests[]] | unique | length' "$WORKDIR/journal_binding.json")
UNBOUND_SYMBOLS=$(jq -r '[.symbols[] | select((.vaultCertFound != true) or (.trustCommitIdBound != true))] | length' "$WORKDIR/journal_binding.json")
TRUST_BINDING_OK=$([ "$UNBOUND_SYMBOLS" = "0" ] && echo true || echo false)
log "acceptance: coldVkd=$COLD_VKD_VERIFIED/$COLD_VKD_TOTAL warmVkd=$WARM_VKD_VERIFIED/$WARM_VKD_TOTAL expected=$N_TARGETS/$EXPECTED_TOTAL symbols=$N_SYMBOLS greenDual=$SYMBOLS_GREEN_DUAL digests(unique/instances)=$DIGEST_UNIQUE/$DIGEST_INSTANCES unbound=$UNBOUND_SYMBOLS"

if [ "$REPORT_COLD_VKD_OK" != "true" ]; then
  FAIL_REASONS+=("acceptance: cold report metrics.vkd = {verified:$COLD_VKD_VERIFIED,total:$COLD_VKD_TOTAL}, expected {verified:$N_TARGETS,total:$EXPECTED_TOTAL}")
fi
if [ "$REPORT_WARM_VKD_OK" != "true" ]; then
  FAIL_REASONS+=("acceptance: warm report metrics.vkd = {verified:$WARM_VKD_VERIFIED,total:$WARM_VKD_TOTAL}, expected {verified:$N_TARGETS,total:$EXPECTED_TOTAL}")
fi
if [ "$N_SYMBOLS" != "$N_TARGETS" ]; then
  FAIL_REASONS+=("acceptance: journal carries $N_SYMBOLS distinct full-cert claim symbol(s), expected $N_TARGETS (see journal_binding.json)")
fi
if [ "$SYMBOLS_GREEN_DUAL" != "true" ]; then
  FAIL_REASONS+=("acceptance: not every journal claim symbol is status=certGreen with verificationTier=dual-verified")
fi
if [ "$DIGEST_INSTANCES" -ne "$N_TARGETS" ] || [ "$DIGEST_UNIQUE" -ne "$N_TARGETS" ]; then
  FAIL_REASONS+=("acceptance: journal claim identityDigests are not one distinct digest per target symbol (unique=$DIGEST_UNIQUE instances=$DIGEST_INSTANCES, expected $N_TARGETS)")
fi
if [ "$TRUST_BINDING_OK" != "true" ]; then
  FAIL_REASONS+=("acceptance: $UNBOUND_SYMBOLS journal claim symbol(s) lack a vault certificate whose trustCommitId equals their journal commit id")
fi

# hard isolation violations
if [ "$HARD_HITS" -gt 0 ]; then
  FAIL_REASONS+=("trace contains $HARD_HITS main runtime-state openat(s)")
fi
if [ "$DRIFT_ATTR" -gt 0 ]; then
  FAIL_REASONS+=("main runtime state written by the traced runs: $DRIFT_ATTR path(s) (see drift_classified.json)")
fi
if [ "$DRIFT_EXT" -gt 0 ]; then
  UNKNOWN_REASONS+=("main runtime state drifted by concurrent EXTERNAL activity ($DRIFT_EXT path(s) outside every traced open) — byte-identity assertion not decidable in this window")
fi
if [ "$MAIN_HEAD_BEFORE" != "$MAIN_HEAD_AFTER" ]; then
  # main is a shared landing surface: a concurrent landing during the run is
  # not runtime-state contamination (and is invisible to the snapshot unless
  # it touches data/trusted/** — which the drift classifier then reports).
  # It does mean the environment was not quiet → UNKNOWN, never FAIL.
  UNKNOWN_REASONS+=("main HEAD moved during run (${MAIN_HEAD_BEFORE:0:12} → ${MAIN_HEAD_AFTER:0:12}) — concurrent landing on the shared reference worktree")
fi
if [ "$MAIN_PATH_OCC" -gt 0 ]; then
  FAIL_REASONS+=("cold journal references the main root path in $MAIN_PATH_OCC record(s)")
fi

# UNKNOWN conditions (fail-closed; no PASS may be minted)
if [ "${#PROVE_FAIL_TARGETS[@]}" -gt 0 ]; then
  # wp5 convention: a prove crash/timeout is infrastructure absence —
  # fail-closed UNKNOWN naming the target, never an isolation verdict.
  UNKNOWN_REASONS+=("ax prove did not produce a verdict for ${#PROVE_FAIL_TARGETS[@]} target run(s): ${PROVE_FAIL_TARGETS[*]}")
fi
if [ "$DETECTOR_OK" != "true" ]; then
  UNKNOWN_REASONS+=("detector negative control failed — analyzer cannot prove it observes main-runtime access")
fi
if [ "$R3_RESOLVED" != "true" ]; then
  UNKNOWN_REASONS+=("$R3_REASON")
fi
if [ "$SCOPE_LOCK_BYTES_EQUAL" -ne 1 ]; then
  UNKNOWN_REASONS+=("scope lock seed byte-inequality (contract input corrupted)")
fi
if [ "$JOURNAL_NEW" -le 0 ]; then
  UNKNOWN_REASONS+=("no journal records created by the cold run — subject binding not observable")
fi
if [ "$UNRESOLVED_MP" -gt 0 ]; then
  UNKNOWN_REASONS+=("$UNRESOLVED_MP journal claim modulePath(s) do not resolve under the cold worktree")
fi
if [ "$DIGEST_EQUAL" != "true" ] || [ "$REPORT_PROJECTION_EQUAL" != "true" ] \
   || [ "$PROVE_EXIT_EQUAL" != "true" ] || [ "$REPORT_EXIT_EQUAL" != "true" ]; then
  UNKNOWN_REASONS+=("warm/cold equivalence mismatch (digest/report/exit)")
fi

if [ "${#FAIL_REASONS[@]}" -gt 0 ]; then
  VERDICT="FAIL" ; EXIT_CODE=4
elif [ "${#UNKNOWN_REASONS[@]}" -gt 0 ]; then
  VERDICT="UNKNOWN" ; EXIT_CODE=3
else
  VERDICT="PASS" ; EXIT_CODE=0
fi

# ── evidence envelope ────────────────────────────────────────────────────────
MAIN_PATH_SAMPLES=$(jq -c \
  '[.cold_prove.hits.hard[0:5], .cold_report.hits.hard[0:5], .cold_digest.hits.hard[0:5],
    .warm_prove.hits.hard[0:5], .warm_report.hits.hard[0:5], .warm_digest.hits.hard[0:5]] | flatten' \
  "$WORKDIR/trace_analysis.json")
OTHER_SAMPLES=$(jq -c \
  '[.cold_prove.hits.other[0:5], .cold_report.hits.other[0:5], .cold_digest.hits.other[0:5],
    .warm_prove.hits.other[0:5], .warm_report.hits.other[0:5], .warm_digest.hits.other[0:5]] | flatten' \
  "$WORKDIR/trace_analysis.json")
COLD_REPORT_PROJ_SHA=$(sha256sum "$WORKDIR/cold_report_stripped.json" | cut -d' ' -f1)
COLD_REPORT_SHA=$(sha256sum "$WORKDIR/cold_report.json" | cut -d' ' -f1)

jq -n \
  --arg verdict "$VERDICT" --argjson exitCode "$EXIT_CODE" \
  --arg mainRoot "$MAIN_ROOT" --arg mainHeadBefore "$MAIN_HEAD_BEFORE" \
  --arg mainHeadAfter "$MAIN_HEAD_AFTER" \
  --arg coldWorktree "$COLD_WT" --arg coldHead "$COLD_HEAD" \
  --arg createdWorktree "$CREATED_WT" \
  --arg stateDir "$STATE_DIR" --arg vaultDir "$VAULT_DIR" \
  --arg scopeLockSha "$SCOPE_LOCK_SHA_SRC" --argjson scopeLockBytesEqual "$SCOPE_LOCK_BYTES_EQUAL" \
  --arg coldDigest "$COLD_DIGEST" --arg warmDigest "$WARM_DIGEST" \
  --argjson coldProveExit "$COLD_PROVE_EXIT" --argjson warmProveExit "$WARM_PROVE_EXIT" \
  --argjson coldReportExit "$COLD_REPORT_EXIT" --argjson warmReportExit "$WARM_REPORT_EXIT" \
  --argjson digestEqual "$DIGEST_EQUAL" --argjson reportProjectionEqual "$REPORT_PROJECTION_EQUAL" \
  --argjson reportsValid "$REPORTS_VALID" \
  --argjson proveExitEqual "$PROVE_EXIT_EQUAL" --argjson reportExitEqual "$REPORT_EXIT_EQUAL" \
  --arg coldReportSha "sha256:$COLD_REPORT_SHA" --arg coldReportProjSha "sha256:$COLD_REPORT_PROJ_SHA" \
  --argjson journalBefore "$JOURNAL_BEFORE" --argjson journalAfter "$JOURNAL_AFTER" --argjson journalNew "$JOURNAL_NEW" \
  --argjson mainPathOcc "$MAIN_PATH_OCC" --argjson unresolvedMp "$UNRESOLVED_MP" \
  --argjson driftTotal "$DRIFT_TOTAL" --argjson driftAttr "$DRIFT_ATTR" --argjson driftExt "$DRIFT_EXT" \
  --argjson vaultCreated "$VAULT_CREATED" --argjson stateCreated "$STATE_CREATED" \
  --argjson hardHits "$HARD_HITS" --argjson allowedHits "$ALLOWED_HITS" \
  --argjson expectedGitHits "$EXPECTED_HITS" --argjson otherHits "$OTHER_HITS" \
  --arg hardSamples "$MAIN_PATH_SAMPLES" --arg otherSamples "$OTHER_SAMPLES" \
  --arg detectorControl "$DETECTOR_CONTROL" --argjson detectorDetected "$DETECTOR_OK" \
  --argjson r3Resolved "$R3_RESOLVED" --arg r3Reason "$R3_REASON" --arg r3Evidence "$R3_FILE" \
  --argjson mainFiles "$MAIN_FILES_BEFORE" \
  --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg axBin "$AX_BIN" --arg workdir "$WORKDIR" \
  --argjson targets "$(printf '%s\n' "${TARGETS[@]}" | jq -R . | jq -s .)" \
  --argjson coldProveExits "$(printf '%s\n' "${COLD_PROVE_EXITS[@]}" | jq -s .)" \
  --argjson warmProveExits "$(printf '%s\n' "${WARM_PROVE_EXITS[@]}" | jq -s .)" \
  --argjson expectedVkdTotal "$EXPECTED_TOTAL" \
  --argjson coldVkdVerified "$COLD_VKD_VERIFIED" --argjson coldVkdTotal "$COLD_VKD_TOTAL" \
  --argjson warmVkdVerified "$WARM_VKD_VERIFIED" --argjson warmVkdTotal "$WARM_VKD_TOTAL" \
  --argjson reportColdVkdOk "$REPORT_COLD_VKD_OK" --argjson reportWarmVkdOk "$REPORT_WARM_VKD_OK" \
  --argjson nSymbols "$N_SYMBOLS" --argjson symbolsGreenDual "$SYMBOLS_GREEN_DUAL" \
  --argjson digestInstances "$DIGEST_INSTANCES" --argjson digestUnique "$DIGEST_UNIQUE" \
  --argjson trustBindingOk "$TRUST_BINDING_OK" --argjson unboundSymbols "$UNBOUND_SYMBOLS" \
  --argjson proveFailTargets "$(printf '%s\n' "${PROVE_FAIL_TARGETS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')" \
  --argjson failReasons "$(printf '%s\n' "${FAIL_REASONS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')" \
  --argjson unknownReasons "$(printf '%s\n' "${UNKNOWN_REASONS[@]:-}" | jq -R . | jq -s 'map(select(length>0))')" \
  '{
    schemaVersion: 2,
    kind: "cold-replay-acceptance",
    generatedAt: $generatedAt,
    verdict: $verdict,
    exitCode: $exitCode,
    failReasons: $failReasons,
    unknownReasons: $unknownReasons,
    isolationContract: {
      mainRoot: $mainRoot,
      mainHeadBefore: $mainHeadBefore,
      mainHeadAfter: $mainHeadAfter,
      mainRuntimeFilesSnapshotted: $mainFiles,
      coldWorktree: $coldWorktree,
      coldHead: $coldHead,
      coldWorktreeCreated: ($createdWorktree == "1"),
      targets: $targets
    },
    contractInputs: {
      scopeLockPath: "data/verification_scope.lock",
      scopeLockSha256: $scopeLockSha,
      scopeLockSeedBytesEqual: $scopeLockBytesEqual
    },
    runs: {
      stateDir: $stateDir, vaultDir: $vaultDir, axBin: $axBin,
      targets: $targets,
      coldProveExits: $coldProveExits, warmProveExits: $warmProveExits,
      coldProveExit: $coldProveExit, warmProveExit: $warmProveExit,
      coldReportExit: $coldReportExit, warmReportExit: $warmReportExit,
      coldCanonicalDigest: $coldDigest, warmCanonicalDigest: $warmDigest,
      digestEqual: $digestEqual, reportProjectionEqual: $reportProjectionEqual,
      reportsValidJson: $reportsValid,
      proveExitEqual: $proveExitEqual, reportExitEqual: $reportExitEqual,
      proveFailures: $proveFailTargets,
      coldReportSha256: $coldReportSha, coldReportVolatileStrippedSha256: $coldReportProjSha,
      volatileKeysMirroredFrom: "src/core/utils/canonical_projection.nim volatileKeys (SSOT)"
    },
    acceptanceAssertions: {
      expectedVkd: {verified: ($targets | length), total: $expectedVkdTotal},
      coldReportVkd: {verified: $coldVkdVerified, total: $coldVkdTotal, ok: $reportColdVkdOk},
      warmReportVkd: {verified: $warmVkdVerified, total: $warmVkdTotal, ok: $reportWarmVkdOk},
      journalDistinctSymbols: $nSymbols,
      journalAllCertGreenDual: $symbolsGreenDual,
      journalIdentityDigests: {instances: $digestInstances, unique: $digestUnique,
        ok: (($digestInstances == ($targets | length)) and ($digestUnique == ($targets | length)))},
      vaultTrustCommitBinding: {unboundSymbols: $unboundSymbols, ok: $trustBindingOk,
        contract: "each journal claim symbol must have a vault certificate whose trustCommitId equals its journal commit id"},
      proveTimeoutsOrCrashes: $proveFailTargets
    },
    coldArtifacts: {
      journalRecordsBefore: $journalBefore, journalRecordsAfter: $journalAfter,
      journalRecordsCreated: $journalNew,
      vaultCreated: $vaultCreated, stateProofFileCreated: $stateCreated
    },
    mainRuntimeDrift: {
      total: $driftTotal, harnessAttributable: $driftAttr, external: $driftExt,
      classification: "drifted path present among traced openat paths → attributable (FAIL); absent from every traced open → concurrent external activity (UNKNOWN)",
      details: "$WORKDIR/drift_classified.json"
    },
    traceAssertion: {
      tool: "strace -f -y -e trace=openat",
      mainRuntimeStatePrefixes: ["data/trusted/", "logs/", ".axiom/"],
      allowList: {
        "data/verification_scope.lock": "tracked contract input (execution-contract snapshot)",
        "src/verification/certificates/**": "documented reference store read (proof_hydration.nim DEBT#433)"
      },
      expectedNonRuntime: {".git/**": "git worktree backpointer to common dir — not runtime state"},
      mainRuntimeHits: $hardHits, mainRuntimeHitSamples: ($hardSamples | fromjson? // []),
      allowListHits: $allowedHits, expectedGitHits: $expectedGitHits,
      otherMainRootHits: $otherHits, otherMainRootSamples: ($otherSamples | fromjson? // [])
    },
    detectorNegativeControl: {
      planted: $detectorControl, detected: $detectorDetected,
      contract: "a deliberate main-runtime read MUST be flagged; an undetectable access makes PASS vacuous"
    },
    subjectBinding: {
      mainPathOccurrencesInColdArtifacts: $mainPathOcc,
      unresolvedModulePaths: $unresolvedMp,
      journalRecordsChecked: $journalNew,
      journal: "$WORKDIR/journal_binding.json",
      traceAnalysis: "$WORKDIR/trace_analysis.json"
    },
    r3IncR3_001Gate: {
      authority: $r3Evidence,
      resolved: $r3Resolved,
      reason: $r3Reason,
      policy: "PASS is unreachable while relocation invariance (pathIndependentProjectionEqual / subjectRunProjectionHashEqual) is absent or expired — no false PASS (INC-R3-001)"
    }
  }' > "$OUT" 2>"$WORKDIR/envelope_error.log" \
  || die "evidence envelope write failed: $(cat "$WORKDIR/envelope_error.log")"

# fix the artifact paths that had to stay literal inside the jq program
jq '.subjectBinding.journal = $j | .subjectBinding.traceAnalysis = $t
    | .mainRuntimeDrift.details = $d' \
  --arg j "$WORKDIR/journal_binding.json" --arg t "$WORKDIR/trace_analysis.json" \
  --arg d "$WORKDIR/drift_classified.json" \
  "$OUT" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"

log "verdict=$VERDICT exit=$EXIT_CODE evidence=$OUT"

if [ "$CLEAN_AFTER" -eq 1 ] && [ "$CREATED_WT" -eq 1 ] && [ "$VERDICT" != "FAIL" ]; then
  git -C "$MAIN_ROOT" worktree remove --force "$COLD_WT" >/dev/null 2>&1 || true
  log "cold worktree removed (--clean)"
else
  log "cold worktree kept for inspection: $COLD_WT"
fi

exit "$EXIT_CODE"
