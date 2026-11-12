#!/usr/bin/env bash
#
# e4e5_snapshot.sh — freeze the current E-4/E-5 collection into an immutable,
# content-hashed snapshot (the collection/confirmatory boundary, §5.6).
#
# What it does (write-once):
#   * copies data/e4e5/{ledger.json, classification_report.json,
#     collection_log.jsonl} into data/e4e5/snapshots/<UTC-stamp>/
#   * writes manifest.json recording, per frozen file, size + sha256; the
#     snapshot_content_sha256 hashes the sorted "sha256  path" line set —
#     this is the snapshot's content identity
#   * embeds the generation census (G_B/G_C, degenerate flags) and the
#     duration-estimand denominators (total vs observable) read from the
#     frozen classification report — the census math lives ONLY in
#     tools/ci/e4e5_classify.sh; this tool embeds, never re-derives
#   * confirms the frozen ledger's own collected_at against the live file
#     (a snapshot must freeze a ledger, not a half-written file)
#
# Immutability contract:
#   * the target directory is created with noclobber semantics — an existing
#     snapshot is NEVER mutated; a colliding stamp HARD-FAILS (history
#     revision banned; new dated records only)
#   * frozen file bytes are verified by content hash at confirmatory
#     extraction time (tools/ci/e4e5_confirm_extract.sh)
#   * the manifest's single mutable section is
#     confirmatory_extraction.attempts — an APPEND-ONLY list written by the
#     confirmatory extractor (completion marker / attempt tombstones).
#     Frozen sections are hash-pinned; local tampering is detectable via git
#     history (data/ is version-controlled)
#
# Usage: e4e5_snapshot.sh [--data-dir data/e4e5] [--now ISO8601]
# Exit codes: 0 = snapshot frozen; 1 = hard failure (missing/corrupt inputs,
#             collision with an existing snapshot); 2 = usage error.

set -euo pipefail

DATA_DIR="data/e4e5"
NOW_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --data-dir) DATA_DIR="$2"; shift 2 ;;
    --now)      NOW_OVERRIDE="$2"; shift 2 ;;
    -h|--help)  sed -n '2,44p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--data-dir DIR] [--now ISO8601]" >&2; exit 2 ;;
  esac
done

command -v jq      >/dev/null 2>&1 || { echo "[e4e5-snapshot] FAIL: jq not available" >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { echo "[e4e5-snapshot] FAIL: sha256sum not available" >&2; exit 2; }

LEDGER="$DATA_DIR/ledger.json"
REPORT="$DATA_DIR/classification_report.json"
CLOG="$DATA_DIR/collection_log.jsonl"
for f in "$LEDGER" "$REPORT" "$CLOG"; do
  [ -s "$f" ] || { echo "[e4e5-snapshot] FAIL: required input missing/empty: $f (run collect + classify first)" >&2; exit 1; }
  jq -e . "$f" >/dev/null 2>&1 || { echo "[e4e5-snapshot] FAIL: not valid JSON: $f" >&2; exit 1; }
done
[ "$(jq -r '.schema' "$REPORT")" = "axiom.e4e5.classification/2" ] \
  || { echo "[e4e5-snapshot] FAIL: classification report schema is $(jq -r '.schema' "$REPORT") — expected axiom.e4e5.classification/2 (re-run classify for the generation census)" >&2; exit 1; }

CREATED_AT="${NOW_OVERRIDE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
STAMP="$(printf '%s' "$CREATED_AT" | sed -E 's/^([0-9-]+)T([0-9:]+)Z$/\1T\2Z/; s/[-:]//g')"
[ -n "$STAMP" ] || { echo "[e4e5-snapshot] FAIL: cannot derive stamp from $CREATED_AT" >&2; exit 2; }

SNAP_DIR="$DATA_DIR/snapshots/$STAMP"
if [ -e "$SNAP_DIR" ]; then
  echo "[e4e5-snapshot] HARD-FAIL: snapshot $SNAP_DIR already exists — snapshots are immutable, never overwritten (history revision banned)" >&2
  exit 1
fi
mkdir -p "$SNAP_DIR"
# A freeze that fails midway must not leave a half-written snapshot behind.
trap 'rm -rf "$SNAP_DIR"' ERR
# noclobber guard belt-and-suspenders: refuse to clobber any pre-existing file
set -C

cp "$LEDGER"  "$SNAP_DIR/ledger.json"
cp "$REPORT"  "$SNAP_DIR/classification_report.json"
cp "$CLOG"    "$SNAP_DIR/collection_log.jsonl"
set +C

# Hash-pin every frozen file (paths relative to the snapshot dir).
FILES_TSV="$SNAP_DIR/.files.tsv"
: > "$FILES_TSV"
for f in ledger.json classification_report.json collection_log.jsonl; do
  printf '%s\t%s\t%s\n' "$f" "$(sha256sum "$SNAP_DIR/$f" | cut -d' ' -f1)" "$(wc -c < "$SNAP_DIR/$f" | tr -d ' ')" >> "$FILES_TSV"
done
CONTENT_SHA="$(awk -F'\t' '{print $2 "  " $1}' "$FILES_TSV" | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1)"

# Census + denominators are EMBEDDED from the frozen classification report
# (SSOT for the math is the classifier); validate their presence so a stale
# schema-/1 report cannot be silently frozen.
for k in n_B_total_eligible_observations n_C_total_eligible_observations \
         n_B_observable_duration n_C_observable_duration \
         n_B_reused_skips n_C_reused_skips; do
  jq -e --arg k "$k" '.counts[$k] | type == "number"' "$SNAP_DIR/classification_report.json" >/dev/null \
    || { echo "[e4e5-snapshot] FAIL: classification report .counts.$k missing/not a number" >&2
         rm -rf "$SNAP_DIR"; exit 1; }
done
jq -e '.counts.generation_census.B.G | type == "number"' "$SNAP_DIR/classification_report.json" >/dev/null \
  || { echo "[e4e5-snapshot] FAIL: classification report lacks generation_census" >&2
       rm -rf "$SNAP_DIR"; exit 1; }

jq -n \
  --arg schema "axiom.e4e5.snapshot_manifest/1" \
  --arg id "$STAMP" \
  --arg created "$CREATED_AT" \
  --arg content_sha "$CONTENT_SHA" \
  --arg ledger_collected "$(jq -r '.collected_at' "$SNAP_DIR/ledger.json")" \
  --arg report_generated "$(jq -r '.generated_at' "$SNAP_DIR/classification_report.json")" \
  --argjson window "$(jq -c '.window' "$SNAP_DIR/ledger.json")" \
  --arg ledger_schema "$(jq -r '.schema' "$SNAP_DIR/ledger.json")" \
  --argjson census "$(jq -c '.counts.generation_census' "$SNAP_DIR/classification_report.json")" \
  --argjson n_b_total "$(jq '.counts.n_B_total_eligible_observations' "$SNAP_DIR/classification_report.json")" \
  --argjson n_c_total "$(jq '.counts.n_C_total_eligible_observations' "$SNAP_DIR/classification_report.json")" \
  --argjson n_b_obs "$(jq '.counts.n_B_observable_duration' "$SNAP_DIR/classification_report.json")" \
  --argjson n_c_obs "$(jq '.counts.n_C_observable_duration' "$SNAP_DIR/classification_report.json")" \
  --argjson n_b_reused "$(jq '.counts.n_B_reused_skips' "$SNAP_DIR/classification_report.json")" \
  --argjson n_c_reused "$(jq '.counts.n_C_reused_skips' "$SNAP_DIR/classification_report.json")" \
  --rawfile files_tsv "$FILES_TSV" \
  '{
    schema: $schema,
    snapshot_id: $id,
    created_at: $created,
    frozen_from: {ledger_collected_at: $ledger_collected,
                  classification_generated_at: $report_generated,
                  ledger_schema: $ledger_schema},
    window: $window,
    content: ({files: ($files_tsv | split("\n") | map(select(length > 0)
                | (split("\t") | {path: .[0], sha256: .[1], bytes: (.[2]|tonumber)}))
                | sort_by(.path))} +
               {snapshot_content_sha256: $content_sha,
                algorithm: "sha256 of the \u0022sha256  path\u0022 line set over content.files, sorted by path"}),
    census: {generation_census: $census,
             n_B_total_eligible: $n_b_total, n_C_total_eligible: $n_c_total,
             n_B_observable_duration: $n_b_obs, n_C_observable_duration: $n_c_obs,
             n_B_reused_skips: $n_b_reused, n_C_reused_skips: $n_c_reused},
    confirmatory_extraction: {attempts: [],
      note: "append-only; written ONLY by tools/ci/e4e5_confirm_extract.sh — one confirmatory extraction per snapshot (§5.6 single analysis)"},
    immutability: "frozen files are hash-pinned; this manifest is never rewritten except for the append-only confirmatory_extraction.attempts list; snapshots are never deleted or merged"
  }' > "$SNAP_DIR/manifest.json.tmp"
# Atomic publication: the manifest appears complete or not at all.
mv "$SNAP_DIR/manifest.json.tmp" "$SNAP_DIR/manifest.json"

rm -f "$FILES_TSV"

echo "[e4e5-snapshot] frozen: $SNAP_DIR"
echo "[e4e5-snapshot] content sha256: $CONTENT_SHA"
jq -r '"[e4e5-snapshot] census: G_B=\(.census.generation_census.B.G) G_C=\(.census.generation_census.C.G) | n_B total/observable=\(.census.n_B_total_eligible)/\(.census.n_B_observable_duration) n_C total/observable=\(.census.n_C_total_eligible)/\(.census.n_C_observable_duration)"' "$SNAP_DIR/manifest.json"
echo "[e4e5-snapshot] confirmatory extraction must target this snapshot id: $STAMP"
exit 0
