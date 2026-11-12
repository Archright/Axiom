#!/usr/bin/env bash
# generate_gate_closure_manifests.sh — VS-T canonical dependency authority.
#
# Generates per-gate closure manifests (compiler truth) by running
# `nim genDepend` through the PRODUCTION capture contract pp_capture_manifest
# (.githooks/pre-push Part 4a, sourced with PREPUSH_SOURCE_ONLY=1 — reused,
# never reimplemented here). GenDepend quirks and the fail-closed artifact
# validation contract live in docs/spec/nim_gendepend_quirks.md.
#
# Contract (VS-T, docs/evidence/vst_dependency_authority_handoff_2026-11-08.md):
#   $1 repoRoot      — absolute repository root
#   $2 targetsFile   — lines of "<gateId>\t<absolute main module .nim>"
#   $3 outDir        — manifest output directory (.axiom/cache/gate_closure)
#   $4 flags         — canonical genDepend profile string (authority:
#                      src/core/gate/closure_manifest.nim genDependProfile)
#
# Output per target: <outDir>/<module>.manifest with an identity header
# (SCHEMA/MAIN/NIM_SHA256/NIM_VERSION/FLAGS/CWD_CONTRACT) followed by the
# sorted CLOSURE:/PROBE: lines from pp_capture_manifest. Writes are atomic
# (tmp + mv). ANY capture failure fails the whole run (exit 1) — a gate with
# no valid manifest gets no CAS key and fails closed at read time; it is
# never silently excluded (§0.9 theater prohibition).
#
# Determinism: every genDepend capture is fully isolated — one throwaway
# mktemp CWD+nimcache per call (the /tmp-CWD contract is load-bearing: quirk
# 5/6 — a CWD containing axiom.nimble loses nimble packages; a repo CWD
# makes config.nims quit), and no two captures share any mutable path
# (distinct main modules — duplicate basenames are refused below; distinct
# manifest outputs; the DEBT#457/DEBT#481 shared-nimcache/shared-output
# collision class is structurally absent). Captures therefore run
# concurrently (DEBT#522 parallel-capture follow-up, 2026-11-09): manifest
# bytes are a pure function of (sources, flags, toolchain) —
# scheduling-independent (VS-T §6 D: 54/54 byte-identical across
# regenerations). Worker count changes wall clock only, never output. The
# exit status of genDepend is meaningless without graphviz (quirk 1) —
# pp_capture_manifest validates the .deps artifact itself, and ANY capture
# failure still fails the whole run (exit 1, fail-closed).
#
# Cleanup: pp_capture_manifest removes the .dot file it created next to the
# main module (quirk 3); this script adds a belt-and-braces EXIT trap that
# removes any .dot this run created next to a target main module — stray
# debris in the repository would trip the language-ban gate in CI.

set -uo pipefail

REPO_ROOT="${1:-}"
TARGETS_FILE="${2:-}"
OUT_DIR="${3:-}"
FLAGS="${4:-}"

fail() {
    echo "[closure-manifest] FAIL: $*" >&2
    exit 1
}

[ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT" ] || fail "repoRoot missing: '$REPO_ROOT'"
[ -n "$TARGETS_FILE" ] && [ -f "$TARGETS_FILE" ] || fail "targetsFile missing: '$TARGETS_FILE'"
[ -n "$OUT_DIR" ] || fail "outDir missing"
[ -n "$FLAGS" ] || fail "flags missing"
NIMBIN="$(command -v nim 2>/dev/null)" || fail "nim not found on PATH"
# Probe paths in closure files are CWD-relative strings (quirk 4) — resolve
# them against the repository root, independent of the caller's CWD.
cd "$REPO_ROOT" || fail "cannot cd to repoRoot"

# Source the production capture contract (VS-1 / pre-commit precedent).
PREPUSH_HOOK="$REPO_ROOT/.githooks/pre-push"
[ -f "$PREPUSH_HOOK" ] || fail "capture contract missing: $PREPUSH_HOOK"
PREPUSH_SOURCE_ONLY=1
# shellcheck source=/dev/null
source "$PREPUSH_HOOK" || fail "sourcing capture contract failed"
unset PREPUSH_SOURCE_ONLY

mkdir -p "$OUT_DIR" || fail "cannot create $OUT_DIR"

# Identity header values (validated at read time by closure_manifest.nim).
NIM_SHA256="$(sha256sum "$NIMBIN" 2>/dev/null | cut -d' ' -f1)"
[ "${#NIM_SHA256}" -eq 64 ] || fail "nim binary sha256 unavailable"
NIM_VERSION="$(nim --version 2>/dev/null | head -c 4096 | tr '\n' '\001' | sed 's/\x01/\\n/g')"
[ -n "$NIM_VERSION" ] || fail "nim --version produced no output"

# Targets: gateId<TAB>abs main module. Duplicate module basenames would make
# the manifest filename ambiguous — refuse (fail-closed) instead of silently
# overwriting one gate's manifest with another's.
declare -a T_IDS=() T_MAINS=() T_MODS=()
declare -A SEEN_MODS=()
while IFS=$'\t' read -r gid main; do
    [ -n "$gid" ] && [ -n "$main" ] || fail "malformed targets line"
    [ -f "$main" ] || fail "target main module missing: $main"
    mod="$(basename "$main" .nim)"
    if [ -n "${SEEN_MODS[$mod]:-}" ]; then
        fail "duplicate module basename '$mod' (gates ${SEEN_MODS[$mod]} and $gid) — manifest filename ambiguous"
    fi
    SEEN_MODS["$mod"]="$gid"
    T_IDS+=("$gid")
    T_MAINS+=("$main")
    T_MODS+=("$mod")
done < "$TARGETS_FILE"
[ "${#T_IDS[@]}" -gt 0 ] || fail "no targets"

# Belt-and-braces .dot cleanup (quirk 3): record pre-existing .dot files next
# to each main module; the EXIT trap removes any .dot this run created.
declare -A DOT_PRE=()
for main in "${T_MAINS[@]}"; do
    d="${main%/*}/$(basename "$main" .nim).dot"
    DOT_PRE["$d"]="$([ -e "$d" ] && echo 1 || echo 0)"
done
cleanup_dot() {
    local main d
    for main in "${T_MAINS[@]}"; do
        d="${main%/*}/$(basename "$main" .nim).dot"
        if [ "${DOT_PRE[$d]}" = "0" ] && [ -e "$d" ]; then
            rm -f "$d"
            echo "[closure-manifest] removed stray .dot: $d" >&2
        fi
    done
}
# Per-job verdict state (rc + log), so reporting stays in target order and
# deterministic regardless of completion order. The EXIT trap removes it.
WORK_DIR="$(mktemp -d)" || fail "mktemp -d failed for job state"
trap 'rm -rf "$WORK_DIR"; cleanup_dot' EXIT

# Concurrent capture bound (DEBT#522): AXIOM_CLOSURE_WORKERS bounds
# in-flight captures (default 8, capped by nproc so a 2-vCPU CI runner
# runs 2). It changes wall clock only — never manifest bytes or verdicts.
CLOSURE_WORKERS="${AXIOM_CLOSURE_WORKERS:-8}"
case "$CLOSURE_WORKERS" in ''|*[!0-9]*) CLOSURE_WORKERS=8 ;; esac
[ "$CLOSURE_WORKERS" -ge 1 ] 2>/dev/null || CLOSURE_WORKERS=8
NPROC_AVAIL="$(nproc 2>/dev/null || echo 1)"
[ "$NPROC_AVAIL" -ge 1 ] 2>/dev/null || NPROC_AVAIL=1
[ "$CLOSURE_WORKERS" -gt "$NPROC_AVAIL" ] && CLOSURE_WORKERS="$NPROC_AVAIL"

run_capture_job() {
    # $1 job index, $2 gateId, $3 main module, $4 module basename. Every
    # path this job touches is exclusive to it: its mktemp capture file,
    # pp_capture_manifest's throwaway CWD+nimcache, the .dot next to its
    # main module, and its manifest output (duplicate basenames were
    # refused above). The job records its verdict in $WORK_DIR and always
    # returns 0 — the caller decides fail-closed from the rc files. On
    # failure the log carries the exact serial-contract message; the
    # reporting loop is the single place that prints it (via fail).
    local idx="$1" gid="$2" main="$3" mod="$4"
    local cap out tmpout
    cap="$(mktemp)" || {
        echo "mktemp failed" >"$WORK_DIR/$idx.log"
        echo 1 >"$WORK_DIR/$idx.rc"
        return 0
    }
    if ! pp_capture_manifest "$main" "$FLAGS" "$cap"; then
        rm -f "$cap"
        echo "genDepend closure capture failed for $gid ($main) — UNKNOWN, fail-closed" >"$WORK_DIR/$idx.log"
        echo 1 >"$WORK_DIR/$idx.rc"
        return 0
    fi
    out="$OUT_DIR/$mod.manifest"
    tmpout="$out.tmp.$$.$idx"
    if ! {
        printf 'SCHEMA=gate-closure-manifest/1\n'
        printf 'MAIN=%s\n' "$main"
        printf 'NIM_SHA256=%s\n' "$NIM_SHA256"
        printf 'NIM_VERSION=%s\n' "$NIM_VERSION"
        printf 'FLAGS=%s\n' "$FLAGS"
        printf 'CWD_CONTRACT=mktemp-d-per-run\n'
        cat "$cap"
    } > "$tmpout"; then
        rm -f "$cap" "$tmpout"
        echo "manifest write failed for $gid" >"$WORK_DIR/$idx.log"
        echo 1 >"$WORK_DIR/$idx.rc"
        return 0
    fi
    rm -f "$cap"
    if ! mv -f "$tmpout" "$out"; then
        echo "atomic manifest install failed for $gid" >"$WORK_DIR/$idx.log"
        echo 1 >"$WORK_DIR/$idx.rc"
        return 0
    fi
    echo "[closure-manifest] $gid -> $out ($(grep -c '^CLOSURE:' "$out") closure, $(grep -c '^PROBE:' "$out") probe)" >"$WORK_DIR/$idx.log"
    echo 0 >"$WORK_DIR/$idx.rc"
}

active=0
for i in "${!T_IDS[@]}"; do
    if [ "$active" -ge "$CLOSURE_WORKERS" ]; then
        # Reap exactly one finished job before launching the next.
        wait -n 2>/dev/null || true
        active=$((active - 1))
    fi
    run_capture_job "$i" "${T_IDS[$i]}" "${T_MAINS[$i]}" "${T_MODS[$i]}" &
    active=$((active + 1))
done
wait

# Verdicts are read back in target order: deterministic reporting, and ANY
# capture failure fails the whole run exactly as the serial contract did
# (missing rc file = the job itself died — UNKNOWN, fail-closed).
manifest_count=0
for i in "${!T_IDS[@]}"; do
    gid="${T_IDS[$i]}"
    msg="$(cat "$WORK_DIR/$i.log" 2>/dev/null)"
    if [ "$(cat "$WORK_DIR/$i.rc" 2>/dev/null)" != "0" ]; then
        fail "${msg:-job died without a verdict for $gid (rc file missing) — UNKNOWN, fail-closed}"
    fi
    echo "$msg"
    manifest_count=$((manifest_count + 1))
done

echo "[closure-manifest] OK — $manifest_count manifest(s) generated (parallel genDepend, $CLOSURE_WORKERS worker(s))"
exit 0
