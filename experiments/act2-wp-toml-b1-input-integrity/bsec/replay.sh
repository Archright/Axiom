#!/usr/bin/env bash
# replay.sh — the ONE evidence-replay protocol for
# experiments/act2-wp-toml-b1-input-integrity. Exactly four verbs, no more:
#
#   replay.sh verify      READ-ONLY.
#     1. every MANIFEST entry (kind=file|archive|member) recomputed
#     2. coverage — every plain file under bsec/offline/ and every *.tar.gz
#        under the experiment MUST be listed (no unlisted bulk, ever)
#     3. subject consumed files: sha256 + git blob id vs the live READ-ONLY
#        checkout (offline/subject/blobs_consumed_sha256.tsv)
#     4. verdict_generations.tsv ledger — schema + append-only hash chain +
#        reference integrity (fail-closed):
#          - exact header; event_kind always 'verdict_generation'
#          - unique event_id; 'at' format-checked only (recording-time value,
#            NEVER regenerated or compared to current time on replay)
#          - supersedes: empty, or an EARLIER row's event_id of the SAME
#            lineage (same triple_id); cross-lineage or backward reference or
#            a fork (one parent superseded twice) is a hard failure
#          - exactly ONE current (non-superseded) generation per lineage
#          - payload: one-line JSON with exactly the keys
#            verdict,tuple,rule_id,rule_hash,input_ref,snapshot_ref,reason,
#            evidence_refs ; verdict in {GO,NO-GO,N/A,UNKNOWN};
#            rule_hash = 64-hex; evidence_refs = non-empty array of strings
#          - evidence_ref / input_ref / snapshot_ref / evidence_refs[*] must
#            resolve to an existing file (experiment-root- or bsec-relative;
#            '#fragment' anchors stripped)
#     6. ledger git-recorded-domain gates (the ledger is NOT MANIFEST-pinned;
#        one integrity domain per artifact):
#          - Test A (fail-closed ALWAYS): the ledger must be committed and
#            byte-identical to HEAD. An entirely untracked record file fails
#            ("untracked record file") until its first landing; uncommitted
#            or staged changes fail (append + commit land as ONE coherent
#            generation).
#          - Test B (past-generation immutability): vs a trusted base
#            (AXIOM_LEDGER_BASE or merge-base with origin/main). VACUOUS PASS
#            while the ledger is absent at the base — or while no trusted
#            base exists at all: a brand-new ledger has no past generations
#            to protect, so the first PR that introduces it can always land
#            ("prefix binding starts at first landing"). Once the ledger IS
#            present at the base, appends are allowed and any byte inside
#            the preserved prefix changed — or a shrunk file — fails.
#     verify never writes anything: every byte it touches is read-only; its
#     only scratch (archive extraction for member hashing) lives under /tmp
#     and is removed. Exit: 0 verified; 1 any failure.
#
#   replay.sh run
#     TRUSTED-TREE ONLY: run compiles and executes code (the harness, the
#     canonicalization adapter, the recorded build command), so it refuses to
#     run when AXIOM_TARGET_TREE selects a tree other than this script's own
#     repo — candidate code is NEVER executed. CI runs verify/judge ONLY;
#     run never executes candidate code.
#     Replays the pinned snapshot: builds from the hash-verified bundle
#     (deps.tar.gz staging only, NEVER ~/.nimble/pkgs2), runs the 7 pinned
#     cases TWICE as independent executions A/B, and checks byte-identity:
#       - per-case raw outputs vs the recorded projection
#         (offline/observations/projection.sha256)
#       - canonical evidence identity across A and B, computed by the single
#         canonicalization authority
#         src/core/utils/canonical_projection.nim::canonicalProjectionHash
#         (volatile keys + top-level runtimeMeta excluded BY THAT FUNCTION —
#         never by a second exclusion list). Runtime metadata (stamp, date,
#         subject head, batch marker) lives in the runtimeMeta envelope and in
#         metadata.txt, outside the identity domain.
#     Gates: verify passes; subject HEAD == snapshot.subject_head and porcelain
#     clean; toolchain == nim 2.2.10 (git hash pinned).
#     Exit: 0 replay matches the record; 2 projection/canonical divergence
#     (divergent observations are NEVER promoted to judgments); 1 INVALID
#     environment.
#
#   replay.sh judge
#     Re-derives verdicts as a PURE function of observations + rules
#     (rules/rule_table.tsv — TOTAL, first match wins, no match/undefined ->
#     UNKNOWN) over the recorded observations (the bytes `run` proves
#     live-reproducible; B-SEC-01 rows use the live B-1 defect fact), writing
#     the derivation ONLY to a temporary location under /tmp. It first gates
#     on `verify` (derivation only over verified bytes; INVALID on failure),
#     then compares:
#       - derived verdict vs verdicts_recorded.tsv (both directions; a
#         recorded triple without an observation facts row is INVALID — not
#         re-derivable)
#       - derived verdict/tuple/rule_id vs the CURRENT (head) generation of
#         the verdict lineage in verdict_generations.tsv, including
#         rule_hash == sha256 of the exact matched rule-table row
#       - reason byte-equality: the recorded reason cell is a projection of
#         the ledger head payload.reason — any divergence is a hard failure
#         (projection divergence), independent of the consistency check below
#       - reason consistency: a reason cell that contradicts its own verdict
#         (e.g. verdict NO-GO while the reason says "NOT a NO-GO") is a hard
#         failure; if the reason cites rule ids, the rule that actually
#         derives the verdict must be among them
#     judge NEVER writes to the record and NEVER auto-corrects a value.
#     Exit: 0 derived == recorded == ledger heads; 1 INVALID or mismatch.
#
#   replay.sh freshness     READ-ONLY.
#     The OR predicate against snapshot/judgment_snapshot.tsv (judgment-time
#     baseline): subject HEAD / consumer commits / dep pins / bundle
#     integrity. Prints FRESH or RE-EVALUATE REQUIRED. No evaluation logs are
#     written and no fresh_as_of-style field exists anywhere. Fail-closed: an
#     undeterminable term counts as fired, never as fresh.
#     Exit: 0 FRESH; 1 RE-EVALUATE REQUIRED.
#
# Trust model — TRUSTED script + CANDIDATE data (AXIOM_TARGET_TREE):
#   Every validated path (MANIFEST, offline bundle, rules, recorded verdicts,
#   snapshot, verdict ledger, projection, evidence refs, and the ledger's git
#   record domain) resolves against TARGET_ROOT, defined as
#   ${AXIOM_TARGET_TREE:-<this script's own repo root>}. Unset: the script
#   validates its own tree (historical behavior, byte-identical). Set: the
#   checker EXECUTING from the trusted base commit validates the CANDIDATE
#   tree as DATA ONLY — verify/judge/freshness read candidate bytes and never
#   execute anything from the target tree, and the ledger gates run
#   `git -C "$TARGET_ROOT"` (a candidate without a usable git worktree fails
#   closed with a clear message). `run` is the sole code-executing verb and
#   refuses an external target entirely (CI runs verify/judge ONLY; run never
#   executes candidate code).
#
# Constraints honored: binaries, caches, the canonical-projection adapter and
# all derivation outputs live in /tmp only; the subject repo is opened
# READ-ONLY and stays byte-clean; no verb ever writes to the record.
set -uo pipefail

# Script identity: where this EXECUTING (trusted) copy of the protocol lives.
# Code-executing paths (run verb: build_canonical_tool, harness build) stay
# bound to these; every VALIDATED path below resolves against TARGET_ROOT.
BSEC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXP_ROOT="$(cd "$BSEC_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EXP_ROOT/../.." && pwd)"
# Validation target: the tree whose recorded bytes are checked (candidate tree
# as DATA when AXIOM_TARGET_TREE is set — see the header trust model).
TARGET_ROOT="${AXIOM_TARGET_TREE:-$REPO_ROOT}"
TARGET_ROOT="$(cd "$TARGET_ROOT" 2>/dev/null && pwd)" || {
  echo "replay: AXIOM_TARGET_TREE is not an existing directory: ${AXIOM_TARGET_TREE:-}" >&2
  exit 1
}
TARGET_EXP="$TARGET_ROOT/experiments/act2-wp-toml-b1-input-integrity"
TARGET_BSEC="$TARGET_EXP/bsec"
OFFLINE="$TARGET_BSEC/offline"
MANIFEST="$TARGET_EXP/MANIFEST"
RULES="$TARGET_BSEC/rules/rule_table.tsv"
FACTS="$OFFLINE/consumers/triples_facts.tsv"
RECORDED="$TARGET_BSEC/verdicts_recorded.tsv"
SNAPSHOT="$TARGET_BSEC/snapshot/judgment_snapshot.tsv"
LEDGER="$TARGET_BSEC/verdict_generations.tsv"
PROJECTION="$OFFLINE/observations/projection.sha256"
SUBJECT="${SUBJECT_REPO:-<workspace>/nim-toml-serialization}"
NIM="${NIM:-$(command -v nim)}"
RUNROOT="${RUNROOT:-/tmp/bsec_run_root}"

LEDGER_HEADER=$'event_id\ttriple_id\tevent_kind\tat\tactor\tevidence_ref\tsupersedes\tpayload'
PAYLOAD_KEYS_SORTED="evidence_refs,input_ref,reason,rule_hash,rule_id,snapshot_ref,tuple,verdict"
VERDICT_ENUM_RE='^(GO|NO-GO|N/A|UNKNOWN)$'
AT_FORMAT_RE='^[0-9]{4}-[0-9]{2}-[0-9]{2}([Tt][0-9]{2}:[0-9]{2}(:[0-9]{2})?([Zz]|[+-][0-9]{2}:?[0-9]{2})?)?$'
RULE_HASH_RE='^[0-9a-fA-F]{64}$'

VERIFY_FAIL=0
note_fail() { echo "VERIFY-FAIL: $1"; VERIFY_FAIL=1; }

manifest_has() { # manifest_has <kind> <path> — exact row lookup
  awk -F'\t' -v k="$1" -v r="$2" '$1==k && $2==r {found=1; exit} END{exit !found}' "$MANIFEST"
}

ensure_jq() {
  command -v jq >/dev/null 2>&1 || {
    echo "VERIFY-FAIL: jq is required for ledger/payload validation but was not found (fail-closed)"
    return 1
  }
}

# pf <payload-json> <jq-filter> — extract a string field; empty output on any error
pf() { printf '%s' "$1" | jq -r "$2" 2>/dev/null; }

ref_resolvable() { # ref_resolvable <ref> — '#fragment' anchors stripped; root- or bsec-relative
  local r="${1%%#*}"
  [ -n "$r" ] || return 1
  { [ -f "$TARGET_EXP/$r" ] || [ -f "$TARGET_BSEC/$r" ]; } && return 0
  case "$r" in /*) [ -f "$r" ] && return 0 ;; esac
  return 1
}

norm_defect() { case "$1" in yes) echo present ;; no) echo absent ;; *) echo "$1" ;; esac; }

tuple_canonical() { # tuple_canonical <raw> -> canonical "defect_live|consumer_path|valid_contrast|boundary|artifact"; rc 1 if invalid
  local t="$1" d p c b a
  if [[ "$t" == "{"* ]]; then
    d="$(pf "$t" '.defect_live // empty')"
    p="$(pf "$t" '.consumer_path // empty')"
    c="$(pf "$t" '.valid_contrast // empty')"
    b="$(pf "$t" '.boundary // empty')"
    a="$(pf "$t" '.artifact // empty')"
  else
    IFS='|' read -r d p c b a <<< "$t" || return 1
  fi
  d="$(norm_defect "$d")"
  case "$d" in present|absent|unparseable) ;; *) return 1 ;; esac
  case "$p" in executes|not_used|unknown) ;; *) return 1 ;; esac
  case "$c" in equivalent|differs|unknown) ;; *) return 1 ;; esac
  case "$b" in neutralizes|does_not|unknown) ;; *) return 1 ;; esac
  case "$a" in present|absent) ;; *) return 1 ;; esac
  printf '%s|%s|%s|%s|%s' "$d" "$p" "$c" "$b" "$a"
}

payload_structural_errors() { # payload_structural_errors <payload> <rowlabel> — prints VERIFY-FAIL lines, sets VERIFY_FAIL
  local payload="$1" label="$2" v k refs n i ref
  if ! printf '%s' "$payload" | jq -e 'type=="object"' >/dev/null 2>&1; then
    note_fail "ledger $label: payload is not a valid one-line JSON object"
    return 0
  fi
  k="$(pf "$payload" 'keys|sort|join(",")')"
  [ "$k" = "$PAYLOAD_KEYS_SORTED" ] || note_fail "ledger $label: payload keys mismatch (expected $PAYLOAD_KEYS_SORTED; got ${k:-<unparsable>})"
  v="$(pf "$payload" '.verdict')"
  [[ "$v" =~ $VERDICT_ENUM_RE ]] || note_fail "ledger $label: payload.verdict '$v' not in {GO,NO-GO,N/A,UNKNOWN}"
  v="$(pf "$payload" '.rule_id')"
  [ -n "$v" ] && [ "$v" != "null" ] || note_fail "ledger $label: payload.rule_id empty"
  v="$(pf "$payload" '.rule_hash')"
  [[ "$v" =~ $RULE_HASH_RE ]] || note_fail "ledger $label: payload.rule_hash '$v' is not a 64-hex sha256"
  for k in input_ref snapshot_ref; do
    v="$(pf "$payload" ".$k")"
    if [ -z "$v" ] || [ "$v" = "null" ]; then
      note_fail "ledger $label: payload.$k empty"
    elif ! ref_resolvable "$v"; then
      note_fail "ledger $label: payload.$k does not resolve to an existing file: '$v'"
    fi
  done
  v="$(pf "$payload" '.reason')"
  [ -n "$v" ] && [ "$v" != "null" ] || note_fail "ledger $label: payload.reason empty"
  v="$(tuple_canonical "$(pf "$payload" '.tuple')")" || v=""
  [ -n "$v" ] || note_fail "ledger $label: payload.tuple is not a valid observation tuple (5 enumerated fields)"
  refs="$(pf "$payload" '.evidence_refs | type')"
  [ "$refs" = "array" ] || note_fail "ledger $label: payload.evidence_refs is not a JSON array"
  if [ "$refs" = "array" ]; then
    n="$(pf "$payload" '.evidence_refs | length')"
    [ "${n:-0}" -ge 1 ] 2>/dev/null || note_fail "ledger $label: payload.evidence_refs is empty (a generation must cite evidence)"
    for ((i = 0; i < n; i++)); do
      ref="$(pf "$payload" ".evidence_refs[$i]")"
      if [ -z "$ref" ] || [ "$ref" = "null" ]; then
        note_fail "ledger $label: payload.evidence_refs[$i] is not a string"
      elif ! ref_resolvable "$ref"; then
        note_fail "ledger $label: payload.evidence_refs[$i] does not resolve to an existing file: '$ref'"
      fi
    done
  fi
}

# ----------------------------------------------------------------- verify ----
cmd_verify() {
  local rel want got f n=0 archives=0 members=0 tmpd m mrel mh subj_head tsv path blob want_sha gb unlisted

  if [ ! -f "$MANIFEST" ]; then
    echo "VERIFY-FAIL: MANIFEST missing: $MANIFEST"
    exit 1
  fi
  ensure_jq || exit 1

  echo "== verify: MANIFEST + ledger chain + subject identity (READ-ONLY, fail-closed) =="

  # --- 1. every 'file' entry: recompute sha256
  while IFS="$(printf '\t')" read -r kind rel want; do
    [ "$kind" = "file" ] || continue
    n=$((n+1))
    f="$TARGET_EXP/$rel"
    if [ ! -f "$f" ]; then note_fail "missing file: $rel"; continue; fi
    got="$(sha256sum "$f" | cut -d' ' -f1)"
    [ "$got" = "$want" ] || note_fail "sha256 mismatch: $rel (manifest=$want actual=$got)"
  done < "$MANIFEST"
  echo "file entries checked: $n"

  # --- 2. every 'archive' entry: self-hash, then every 'member' entry vs the
  #        extracted bytes; every tarball member must be recorded (no hidden bulk)
  while IFS="$(printf '\t')" read -r rel want; do
    archives=$((archives+1))
    local t="$TARGET_EXP/$rel"
    if [ ! -f "$t" ]; then note_fail "missing archive: $rel"; continue; fi
    got="$(sha256sum "$t" | cut -d' ' -f1)"
    [ "$got" = "$want" ] || note_fail "archive sha256 mismatch: $rel"
    tmpd="$(mktemp -d)"
    if ! ( cd "$tmpd" && tar -xzf "$t" ); then
      note_fail "archive not extractable: $rel"
    else
      members=0
      while IFS="$(printf '\t')" read -r _ mkind mpath mhash; do
        [ "$mkind" = "member" ] || continue
        m="${mpath#*::}"
        if [ ! -f "$tmpd/$m" ]; then
          note_fail "archive member missing: $mpath"; continue
        fi
        mh="$(sha256sum "$tmpd/$m" | cut -d' ' -f1)"
        [ "$mh" = "$mhash" ] || note_fail "archive member sha256 mismatch: $mpath"
        members=$((members+1))
      done < <(awk -F'\t' -v a="$rel" 'index($2, a"::")==1 {print "x\t"$0}' "$MANIFEST")
      [ "$members" -gt 0 ] || note_fail "no member entries for archive: $rel"
      while IFS= read -r m; do
        mrel="${m#"$tmpd"/}"
        manifest_has member "$rel::$mrel" || note_fail "unlisted archive member: $rel::$mrel"
      done < <(find "$tmpd" -type f | LC_ALL=C sort)
      echo "archive checked: $rel (self + $members members, full coverage)"
    fi
    rm -rf "$tmpd"
  done < <(awk -F'\t' '$1=="archive"{print $2 "\t" $3}' "$MANIFEST")
  [ "$archives" -gt 0 ] || note_fail "no archive entries in MANIFEST (bulk must not silently vanish)"

  # --- 3. coverage: every plain file under bsec/offline/ and every tarball
  #        under the experiment must be listed in MANIFEST
  unlisted=0
  while IFS= read -r f; do
    rel="${f#"$TARGET_EXP"/}"
    if ! manifest_has file "$rel"; then
      note_fail "unlisted bundle file (not in MANIFEST): $rel"
      unlisted=$((unlisted+1))
    fi
  done < <(find "$OFFLINE" -type f | LC_ALL=C sort)
  while IFS= read -r t; do
    rel="${t#"$TARGET_EXP"/}"
    manifest_has archive "$rel" || note_fail "unlisted archive (not in MANIFEST): $rel"
  done < <(find "$TARGET_EXP" -type f -name '*.tar.gz' | LC_ALL=C sort)
  echo "coverage: bsec/offline/ fully listed; all *.tar.gz listed as archives"

  # --- 4. subject consumed files: content sha256 AND git object identity
  if [ ! -d "$SUBJECT" ]; then
    note_fail "subject checkout not found: $SUBJECT"
  else
    subj_head="$(git -C "$SUBJECT" rev-parse HEAD 2>/dev/null || echo UNAVAILABLE)"
    echo "subject HEAD: $subj_head"
    tsv="$OFFLINE/subject/blobs_consumed_sha256.tsv"
    n=0
    while IFS="$(printf '\t')" read -r path blob want_sha; do
      case "$path" in ''|'#'*|path) continue ;; esac
      n=$((n+1))
      f="$SUBJECT/$path"
      if [ ! -f "$f" ]; then note_fail "subject file missing: $path"; continue; fi
      got="$(sha256sum "$f" | cut -d' ' -f1)"
      [ "$got" = "$want_sha" ] || note_fail "subject sha256 mismatch: $path"
      gb="$(git -C "$SUBJECT" rev-parse "HEAD:$path" 2>/dev/null || echo UNAVAILABLE)"
      [ "$gb" = "$blob" ] || note_fail "subject git blob mismatch: $path ($gb != $blob)"
    done < "$tsv"
    echo "subject consumed files checked: $n"
  fi

  # --- 5. verdict_generations.tsv ledger: schema + append-only hash chain +
  #        single current generation per lineage + reference integrity
  ledger_validate

  # --- 6. ledger git-recorded-domain gates: worktree integrity vs HEAD and
  #        byte-prefix immutability vs a trusted base (append-only enforcement)
  ledger_git_gates

  if [ "$VERIFY_FAIL" -ne 0 ]; then
    echo "VERIFY RESULT: FAILED (fail-closed)"
    return 1
  fi
  echo "VERIFY RESULT: OK (every recorded hash verified; ledger chain valid; coverage complete)"
  return 0
}

ledger_validate() {
  local ev triple kind at actor eref sup payload lineno=0 first s t cnt
  local at_re="$AT_FORMAT_RE"

  if [ ! -f "$LEDGER" ]; then
    note_fail "ledger: verdict_generations.tsv missing: $LEDGER (the verdict lineage record is part of the protocol)"
    return 0
  fi

  declare -A EV_LINE EV_TRIPLE EV_SUP PARENT_OF SEEN_TRIPLE HEADS
  local line row hdr
  # Tab-split via read would collapse consecutive tabs and DESTROY rows whose
  # supersedes is empty (chain roots). Re-map tabs to the ASCII unit separator
  # (never present raw in jq-produced JSON) so empty fields survive.
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno+1))
    row="${line//$'\t'/$'\x1f'}"
    ev="" triple="" kind="" at="" actor="" eref="" sup="" payload=""
    IFS=$'\x1f' read -r ev triple kind at actor eref sup payload <<< "$row"
    if [ "$lineno" = 1 ]; then
      hdr="$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$ev" "$triple" "$kind" "$at" "$actor" "$eref" "$sup" "$payload")"
      [ "$hdr" = "$LEDGER_HEADER" ] \
        || note_fail "ledger row 1: header does not match the schema (expected: $(printf '%s' "$LEDGER_HEADER" | tr '\t' '|'))"
      continue
    fi
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$payload" == *$'\x1f'* ]] && { note_fail "ledger row $lineno: more than 8 columns"; continue; }
    [ -n "$payload" ] || { note_fail "ledger row $lineno: fewer than 8 columns (empty payload)"; continue; }
    [ -n "$ev" ] || { note_fail "ledger row $lineno: empty event_id"; continue; }
    [ -n "$triple" ] || { note_fail "ledger row $lineno ($ev): empty triple_id"; continue; }
    [ "$kind" = "verdict_generation" ] || note_fail "ledger row $lineno ($ev): event_kind '$kind' != verdict_generation (only verdict_generation events exist)"
    [ -n "$at" ] || note_fail "ledger row $lineno ($ev): empty 'at'"
    { [ -n "$at" ] && ! [[ "$at" =~ $at_re ]]; } && note_fail "ledger row $lineno ($ev): 'at' is not an ISO-8601 timestamp: '$at'"
    [ -n "$actor" ] || note_fail "ledger row $lineno ($ev): empty actor"
    [ -n "$eref" ] || note_fail "ledger row $lineno ($ev): empty evidence_ref"
    if [ -n "$eref" ] && ! ref_resolvable "$eref"; then
      note_fail "ledger row $lineno ($ev): evidence_ref does not resolve to an existing file: '$eref'"
    fi
    [ -n "${EV_LINE[$ev]:-}" ] && note_fail "ledger row $lineno: duplicate event_id: $ev"
    EV_LINE[$ev]="$lineno"
    EV_TRIPLE[$ev]="$triple"
    SEEN_TRIPLE[$triple]=1
    if [ -n "$sup" ]; then
      EV_SUP[$ev]="$sup"
      PARENT_OF[$sup]=1
    fi
    payload_structural_errors "$payload" "row $lineno ($ev)"
  done < "$LEDGER"

  cnt="${#EV_LINE[@]}"
  if [ "$cnt" -eq 0 ]; then
    note_fail "ledger: no generation rows (an empty ledger affirms nothing — fail-closed)"
    return 0
  fi
  echo "ledger: $cnt generation events, ${#SEEN_TRIPLE[@]} lineages"

  # supersedes: must exist, point to an EARLIER row, and stay in the same lineage
  for ev in "${!EV_SUP[@]}"; do
    s="${EV_SUP[$ev]}"
    t="${EV_TRIPLE[$ev]}"
    if [ -z "${EV_LINE[$s]:-}" ]; then
      note_fail "ledger: $ev supersedes unknown event_id: $s"
    else
      if [ "${EV_LINE[$s]}" -ge "${EV_LINE[$ev]}" ]; then
        note_fail "ledger: $ev supersedes $s which is not an EARLIER row (append-only chain order violated)"
      fi
      if [ "${EV_TRIPLE[$s]}" != "$t" ]; then
        note_fail "ledger: cross-lineage supersedes — $ev (triple $t) supersedes $s (triple ${EV_TRIPLE[$s]})"
      fi
    fi
  done

  # fork: one parent superseded by two events -> ambiguous lineage
  for s in "${!PARENT_OF[@]}"; do
    cnt=0
    for ev in "${!EV_SUP[@]}"; do
      [ "${EV_SUP[$ev]}" = "$s" ] && cnt=$((cnt+1))
    done
    [ "$cnt" -le 1 ] || note_fail "ledger: fork — $s is superseded by $cnt events (a lineage must not branch)"
  done

  # exactly ONE current (non-superseded) generation per lineage
  for t in "${!SEEN_TRIPLE[@]}"; do
    cnt=0
    for ev in "${!EV_LINE[@]}"; do
      if [ "${EV_TRIPLE[$ev]}" = "$t" ] && [ -z "${PARENT_OF[$ev]:-}" ]; then
        cnt=$((cnt+1))
      fi
    done
    [ "$cnt" = 1 ] || note_fail "ledger: triple $t has $cnt current generations (exactly 1 required — ambiguous current verdict)"
    HEADS[$t]=1
  done
  return 0
}

# ledger_git_gates — the ledger lives in the GIT record domain (one integrity
# domain per artifact; ../bsec/README.md), so MANIFEST never pins it. These
# gates enforce its record discipline instead:
#   Test A — worktree/index integrity vs HEAD, fail-closed ALWAYS. `git diff
#            HEAD` never reports untracked files, so index membership is
#            probed first: an entirely untracked ledger is reported as an
#            untracked record file and fails until its first landing commit
#            (append + commit land as ONE coherent generation).
#   Test B — past-generation immutability: the byte prefix recorded at a
#            TRUSTED base must be preserved exactly; appends are allowed, any
#            edit/insert/delete inside the prefix — or shrinking below the
#            base — fails. The base comes from AXIOM_LEDGER_BASE (explicit
#            override) or `git merge-base HEAD origin/main`; it is NEVER
#            derived from the last commit that touched the file (that commit
#            could be the tampering one). Test B is VACUOUS while no prior
#            ledger exists at the base (brand-new ledger: nothing to protect
#            yet) or while no trusted base is resolvable — prefix binding
#            starts at the first landing, so the PR that introduces the
#            ledger can always pass. An explicitly set but unresolvable
#            AXIOM_LEDGER_BASE stays fail-closed (operator error is not a
#            bootstrap state).
# Enforcement authority for landing is the PR/merge-queue required check that
# runs this verb; local runs surface the same violations earlier.
ledger_git_gates() {
  local rel="${LEDGER#"$TARGET_ROOT"/}" base_sha tmp old_size
  command -v git >/dev/null 2>&1 || { note_fail "ledger git gate: git unavailable (fail-closed)"; return 0; }

  # The ledger's git domain is the TARGET tree's worktree (candidate tree as
  # DATA — see the header trust model). Gates A/B bind against that tree's
  # git record, so a data-only copy without a usable worktree fails closed
  # here instead of crashing or passing vacuously.
  if [ "$(git -C "$TARGET_ROOT" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
    note_fail "ledger git gate A: target tree has no usable git worktree: $TARGET_ROOT (Gate A/B bind the ledger to the candidate tree's git record; fail-closed)"
    return 0
  fi

  # Test A — worktree/index integrity vs HEAD. Fail-closed ALWAYS.
  # `git diff HEAD` never reports untracked files, so an entirely untracked
  # ledger is caught by the index-membership probe first: an untracked record
  # file fails Test A until its first landing commit. After that first
  # landing, any worktree/index divergence from HEAD fails.
  if ! git -C "$TARGET_ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
    note_fail "ledger git gate A: $rel is an untracked record file — not in HEAD; land it first (append + commit as one coherent generation; fail-closed)"
  elif ! git -C "$TARGET_ROOT" diff --exit-code HEAD -- "$rel" >/dev/null 2>&1; then
    note_fail "ledger git gate A: $rel differs from HEAD in worktree/index — uncommitted or staged ledger change (append + commit as one coherent generation)"
  fi

  # Test B — past-generation immutability vs a trusted base. VACUOUS until a
  # prior ledger exists at the base: a brand-new ledger has no past
  # generations to protect, so "absent at base" (or no trusted base at all)
  # is a vacuous PASS — prefix binding starts at the first landing, and the
  # PR that introduces the ledger can always land. Once the ledger IS present
  # at the trusted base, the byte prefix recorded there must be preserved
  # exactly: appends allowed; any edit/insert/delete inside the prefix — or
  # shrinking below the base — fails. The base comes from AXIOM_LEDGER_BASE
  # (explicit override) or `git merge-base HEAD origin/main`; it is NEVER
  # derived from the last commit that touched the file (that commit could be
  # the tampering one).
  if [ -n "${AXIOM_LEDGER_BASE:-}" ]; then
    base_sha="$AXIOM_LEDGER_BASE"
  elif git -C "$TARGET_ROOT" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    base_sha="$(git -C "$TARGET_ROOT" merge-base HEAD origin/main 2>/dev/null || true)"
  fi
  if [ -z "${base_sha:-}" ]; then
    echo "ledger git gate B: bootstrap — no trusted base resolved (set AXIOM_LEDGER_BASE or publish origin/main); vacuous pass — prefix binding starts at first landing"
    return 0
  fi
  if ! git -C "$TARGET_ROOT" cat-file -e "${base_sha}^{commit}" 2>/dev/null; then
    note_fail "ledger git gate B: trusted base is not a resolvable commit: $base_sha (fail-closed)"
    return 0
  fi
  tmp="$(mktemp)"
  if ! git -C "$TARGET_ROOT" show "${base_sha}:${rel}" > "$tmp" 2>/dev/null; then
    echo "ledger git gate B: bootstrap — no prior ledger at base $base_sha; vacuous pass — prefix binding starts at first landing"
    rm -f "$tmp"
    return 0
  fi
  old_size="$(wc -c < "$tmp")"
  if ! cmp -s -n "$old_size" "$tmp" "$LEDGER"; then
    note_fail "ledger git gate B: append-only violation vs $base_sha — bytes inside the preserved prefix changed (edit/insert/delete inside history or file shrunk)"
  fi
  rm -f "$tmp"
}

# -------------------------------------------------------------------- run ----
# canonical_hash adapter — the ONLY piece of generated code in this protocol.
# It is an execution adapter over the trust fact
# src/core/utils/canonical_projection.nim (canonicalProjectionHash /
# stripVolatile / isVolatileKey): exclusion semantics are imported, never
# re-implemented. Source is generated into /tmp; binaries and caches stay in
# /tmp (hermetic, pinned nim 2.2.10 + nimble.lock-pinned checksums-0.2.2).
build_canonical_tool() {
  local tool="$RUNROOT/canonical_hash_bin" src="$RUNROOT/canonical_hash.nim"
  local cache="$RUNROOT/nimcache_adapter" log="$RUN_DIR/adapter_build.log"
  local pkgs_root="${NIMBLE_DIR:-$HOME/.nimble/pkgs2}" cdir ncdir
  if [ -x "$tool" ] && "$tool" selftest >/dev/null 2>&1; then
    CANON_TOOL="$tool"
    return 0
  fi
  command -v "$NIM" >/dev/null 2>&1 || { echo "RUN: INVALID — nim compiler not found"; return 1; }
  [ -f "$REPO_ROOT/src/core/utils/canonical_projection.nim" ] || {
    echo "RUN: INVALID — canonicalization authority not found: $REPO_ROOT/src/core/utils/canonical_projection.nim"; return 1; }
  cdir="$(find "$pkgs_root" -maxdepth 1 -type d -name 'checksums-0.2.2-*' 2>/dev/null | LC_ALL=C sort)"
  ncdir="$(printf '%s\n' "$cdir" | grep -c .)"
  [ "$ncdir" = 1 ] || { echo "RUN: INVALID — expected exactly one nimble.lock-pinned checksums-0.2.2 package under $pkgs_root, found $ncdir"; return 1; }
  cdir="$(printf '%s\n' "$cdir" | head -1)"
  mkdir -p "$RUNROOT"
  cat > "$src" <<'ADAPTER_EOF'
import std/[json, os]
import core/utils/canonical_projection

proc die(m: string) = stderr.writeLine("canonical_hash: " & m); quit(3)

if paramCount() < 1: die("usage: canonical_hash {hash|strip|selftest} ...")
case paramStr(1)
of "hash":
  if paramCount() != 2: die("hash <json-file>")
  stdout.writeLine(canonicalProjectionHash(parseFile(paramStr(2))))
of "strip":
  if paramCount() != 3: die("strip <json-file> <out-file>")
  writeFile(paramStr(3), $(stripVolatile(parseFile(paramStr(2)))) & "\n")
of "selftest":
  if not isVolatileKey("generatedAt"): quit(1)
  if not isVolatileKey("parallelOverheadMs"): quit(1)
  let a = parseJson("{\"generatedAt\":\"whenever\",\"value\":7}")
  let b = parseJson("{\"value\":7}")
  if canonicalProjectionHash(a) != canonicalProjectionHash(b): quit(1)
  if canonicalProjectionHash(a) == canonicalProjectionHash(parseJson("{\"value\":8}")): quit(1)
  echo "selftest-ok"
else:
  die("unknown mode: " & paramStr(1))
ADAPTER_EOF
  if ! "$NIM" c --warnings:off --hints:off --path:"$REPO_ROOT/src" --path:"$cdir" \
       --nimcache:"$cache" -o:"$tool" "$src" >"$log" 2>&1; then
    echo "RUN: INVALID — canonical authority adapter failed to compile (see $log)"
    return 1
  fi
  if ! "$tool" selftest >/dev/null 2>&1; then
    echo "RUN: INVALID — canonical authority selftest failed (volatile-key exclusion not behaving per contract)"
    return 1
  fi
  CANON_TOOL="$tool"
  return 0
}

evidence_json() { # evidence_json <cases_dir> <batch> <out> <subject_head> — canonical-domain evidence + runtimeMeta envelope
  local dir="$1" batch="$2" out="$3" subj="$4" spec name tmp_cases
  tmp_cases="$RUN_DIR/evidence_cases_$batch.json"
  : > "$tmp_cases"
  for spec in "${CASES[@]}"; do
    IFS='|' read -r name _mode _input <<< "$spec"
    jq -cn --arg name "$name" \
       --rawfile so "$dir/$name/stdout.txt" \
       --rawfile se "$dir/$name/stderr.txt" \
       --arg ec "$(cat "$dir/$name/exit_code.txt")" \
       '{($name): {exit_code: ($ec|tonumber), stdout: $so, stderr: $se}}' >> "$tmp_cases"
  done
  jq -cn --argjson cases "$(jq -s 'add' "$tmp_cases")" \
     --arg batch "$batch" --arg stamp "$STAMP" --arg subject "$subj" --arg date "$(date -Is)" \
     '{cases: $cases, runtimeMeta: {batch: $batch, run_stamp: $stamp, subject_head: $subject, generatedAt: $date}}' > "$out"
}

cmd_run() {
  local current_subject porcelain nim_ver build_exit name mode input spec

  # Trust boundary (header): run executes code — the harness is compiled from
  # the tree and the recorded build command is eval'd. With an external
  # AXIOM_TARGET_TREE that code would be candidate code, so refuse (fail
  # closed). CI runs verify/judge ONLY; run never executes candidate code.
  if [ "$(cd "$TARGET_ROOT" && pwd -P)" != "$(cd "$REPO_ROOT" && pwd -P)" ]; then
    echo "RUN: INVALID — run verb refuses to execute code from an external target tree — run from the trusted tree only (AXIOM_TARGET_TREE=$TARGET_ROOT, script tree=$REPO_ROOT)"
    exit 1
  fi

  echo "== replay run: build from the verified bundle + 7-case replay (A/B) =="
  STAMP="$(date +%Y%m%dT%H%M%S%z)"
  RUN_DIR="$RUNROOT/run_$STAMP"
  CASES_DIR="$RUN_DIR/cases_a"
  CASES_DIR_B="$RUN_DIR/cases_b"
  mkdir -p "$CASES_DIR" "$CASES_DIR_B" "$RUNROOT"
  echo "run_dir=$RUN_DIR (run metadata — NOT part of the byte-identity domain)"

  echo "-- gate 1: bundle verification"
  if ! cmd_verify; then
    echo "RUN: INVALID — bundle verification failed (fail-closed)"
    exit 1
  fi

  echo "-- gate 2: subject identity (READ-ONLY checks)"
  EXPECTED_SUBJECT="$(awk -F'\t' '$1=="subject_head"{print $3}' "$SNAPSHOT")"
  current_subject="$(git -C "$SUBJECT" rev-parse HEAD 2>/dev/null)"
  [ -n "$current_subject" ] || { echo "RUN: INVALID — subject HEAD unresolvable at $SUBJECT"; exit 1; }
  if [ "$current_subject" != "$EXPECTED_SUBJECT" ]; then
    echo "RUN: INVALID — subject HEAD $current_subject != snapshot $EXPECTED_SUBJECT"
    exit 1
  fi
  porcelain="$(git -C "$SUBJECT" status --porcelain 2>/dev/null)"
  [ -z "$porcelain" ] || { echo "RUN: INVALID — subject working tree dirty: $(echo "$porcelain" | head -3)"; exit 1; }
  echo "subject HEAD=$current_subject porcelain-clean=yes"

  echo "-- gate 3: toolchain identity"
  NIM_GIT_HASH_EXPECTED="bfeb3146d1638b39f69007a4ae5a23e23ae4e5ef"
  nim_ver="$("$NIM" --version 2>&1 || true)"
  echo "$nim_ver" | grep -q "Nim Compiler Version 2.2.10" || { echo "RUN: INVALID — nim version mismatch (expected 2.2.10 line)"; exit 1; }
  echo "$nim_ver" | grep -q "$NIM_GIT_HASH_EXPECTED" || { echo "RUN: INVALID — nim git hash mismatch (expected $NIM_GIT_HASH_EXPECTED)"; exit 1; }
  echo "$(echo "$nim_ver" | head -1) / $(echo "$nim_ver" | grep 'git hash' || echo 'git hash: ?')"

  echo "-- build: from bundle-vendored dependencies only (never ~/.nimble/pkgs2)"
  # Vendored sources ship as the content-addressed archive offline/deps.tar.gz
  # (members keep *.nim.vendored naming: byte-exact upstream copies, invisible
  # to Axiom3's nim-check gate). Members were hash-verified by cmd_verify.
  # Extract into a throwaway staging dir, materialize *.nim at build time;
  # never write into offline/, never consult ~/.nimble/pkgs2.
  DEPS_STAGE="$RUN_DIR/deps_stage"
  rm -rf "$DEPS_STAGE"; mkdir -p "$DEPS_STAGE"
  tar -xzf "$OFFLINE/deps.tar.gz" -C "$DEPS_STAGE"
  ( cd "$DEPS_STAGE" && find . -name '*.nim.vendored' -print ) | while IFS= read -r rel; do
    mv "$DEPS_STAGE/$rel" "$DEPS_STAGE/${rel%.vendored}"
  done
  echo "vendored sources materialized: $(find "$DEPS_STAGE" -name '*.nim' | wc -l)"
  BIN="$RUN_DIR/bin/harness"
  NIMCACHE="$RUN_DIR/nimcache"
  BUILD_CMD="$(grep -v '^#' "$OFFLINE/build/command_template.txt" | sed -e "s|@SUBJECT@|$SUBJECT|g" -e "s|@BSEC@|$BSEC_DIR|g" -e "s|@DEPS@|$DEPS_STAGE|g" -e "s|@NIMCACHE@|$NIMCACHE|g" -e "s|@BIN@|$BIN|g" -e "s|@HARNESS@|$OFFLINE/probes/harness.nim|g" | tr '\n' ' ' | sed 's/\\//g; s/  */ /g; s/^ //; s/ $//')"
  printf '%s\n' "$BUILD_CMD" > "$RUN_DIR/build_cmd.txt"
  ( cd "$RUN_DIR" && eval "$BUILD_CMD" ) > "$RUN_DIR/build_stdout.txt" 2> "$RUN_DIR/build_stderr.txt"
  build_exit=$?
  printf '%s\n' "$build_exit" > "$RUN_DIR/build_exit.txt"
  if [ "$build_exit" -ne 0 ] || [ ! -x "$BIN" ]; then
    echo "RUN: INVALID — build failed (exit $build_exit), see $RUN_DIR/build_stderr.txt"
    exit 1
  fi
  echo "build exit=$build_exit"

  CASES=(
    "t1_baseline_valid|record|t1_baseline_valid.toml"
    "t2_dup_key_then_all_fields|record|t2_dup_key_then_all_fields.toml"
    "t3_all_fields_then_malformed|record|t3_all_fields_then_malformed.toml"
    "aux_i_dup_key_isolated|record|aux_i_dup_key_isolated.toml"
    "aux_ii_unknown_field_isolated|record|aux_ii_unknown_field_isolated.toml"
    "contrast_t2_value_v100|value_v100|contrast_t2_bytes_same_as_t2.toml"
    "contrast_t2_value_default|value_default|contrast_t2_bytes_same_as_t2.toml"
  )

  run_cases() { # run_cases <cases_dir> — one independent execution of all 7 pinned inputs
    local d="$1" spec
    for spec in "${CASES[@]}"; do
      IFS='|' read -r name mode input <<< "$spec"
      mkdir -p "$d/$name"
      "$BIN" "$mode" "$OFFLINE/inputs/$input" > "$d/$name/stdout.txt" 2> "$d/$name/stderr.txt"
      printf '%s\n' "$?" > "$d/$name/exit_code.txt"
    done
  }

  echo "-- cases A: 7 pinned inputs (inputs are MANIFEST-pinned bytes)"
  run_cases "$CASES_DIR"
  for spec in "${CASES[@]}"; do
    IFS='|' read -r name _mode _input <<< "$spec"
    echo "  $name exit=$(cat "$CASES_DIR/$name/exit_code.txt")"
  done

  echo "-- byte-identity: per-case outputs vs the recorded projection"
  ( cd "$CASES_DIR" && find . -type f \( -name stdout.txt -o -name stderr.txt -o -name exit_code.txt \) -print0 | sort -z | xargs -0 sha256sum ) > "$RUN_DIR/projection_now.sha256"
  if diff -u "$PROJECTION" "$RUN_DIR/projection_now.sha256" > "$RUN_DIR/projection_diff.txt" 2>&1; then
    echo "projection: BYTE-IDENTICAL ($(wc -l < "$PROJECTION") files)"
  else
    echo "PROJECTION DIVERGENCE — live per-case outputs differ from the recorded projection."
    echo "Divergent observations are NEVER promoted to judgments. Diff: $RUN_DIR/projection_diff.txt"
    echo "The recorded verdicts are historical records from here on (see replay.sh freshness)."
    exit 2
  fi

  echo "-- determinism: canonical identity of two independent executions (authority: canonicalProjectionHash)"
  run_cases "$CASES_DIR_B"
  if ! build_canonical_tool; then
    echo "RUN: INVALID — canonical projection authority unavailable"
    exit 1
  fi
  evidence_json "$CASES_DIR" "A" "$RUN_DIR/evidence_a.json" "$current_subject"
  evidence_json "$CASES_DIR_B" "B" "$RUN_DIR/evidence_b.json" "$current_subject"
  HASH_A="$("$CANON_TOOL" hash "$RUN_DIR/evidence_a.json")" || { echo "RUN: INVALID — canonical hash (A) failed"; exit 1; }
  HASH_B="$("$CANON_TOOL" hash "$RUN_DIR/evidence_b.json")" || { echo "RUN: INVALID — canonical hash (B) failed"; exit 1; }
  "$CANON_TOOL" strip "$RUN_DIR/evidence_a.json" "$RUN_DIR/evidence_a.canonical.json" || { echo "RUN: INVALID — canonical strip (A) failed"; exit 1; }
  "$CANON_TOOL" strip "$RUN_DIR/evidence_b.json" "$RUN_DIR/evidence_b.canonical.json" || { echo "RUN: INVALID — canonical strip (B) failed"; exit 1; }
  if [ "$HASH_A" != "$HASH_B" ] || ! cmp -s "$RUN_DIR/evidence_a.canonical.json" "$RUN_DIR/evidence_b.canonical.json"; then
    echo "CANONICAL DIVERGENCE — two executions on the same pinned input produced different canonical evidence:"
    echo "  hashA=$HASH_A"
    echo "  hashB=$HASH_B"
    echo "Determinism violation; the canonical artifacts are NOT byte-identical. NEVER promoted to judgments."
    exit 2
  fi
  echo "canonical: IDENTICAL across executions A/B (hash=$HASH_A)"
  echo "  volatile keys + runtimeMeta excluded by canonical_projection.nim's normative list (single authority)"
  echo "  canonical artifacts: $RUN_DIR/evidence_a.canonical.json / evidence_b.canonical.json (/tmp only)"

  if [ -f "$RUNROOT/last_run_canonical.sha256" ]; then
    if [ "$(cat "$RUNROOT/last_run_canonical.sha256")" = "$HASH_A" ]; then
      echo "run-to-run: canonical identity identical to previous run"
    else
      echo "run-to-run: canonical identity CHANGED vs previous run (inputs or derivation changed?)"
    fi
  fi
  printf '%s\n' "$HASH_A" > "$RUNROOT/last_run_canonical.sha256"

  echo "-- observations (extracted defect facts)"
  extract_defect_fact "$CASES_DIR"
  echo "defect_live(B-1 pair)=$DEFECT_LIVE parse_ok=$FACT_PARSE_OK conjunction=$FACT_CONJ"

  {
    echo "run_stamp=$STAMP"
    echo "date=$(date -Is)"
    echo "uname=$(uname -a)"
    echo "subject_head=$current_subject"
    echo "bundle=$BSEC_DIR"
    echo "nim=$(echo "$nim_ver" | head -1)"
    echo "canonical_evidence_hash=$HASH_A"
    echo "canonical_identity_authority=src/core/utils/canonical_projection.nim::canonicalProjectionHash"
  } > "$RUN_DIR/metadata.txt"

  echo "RUN: PASS — raw projection byte-identical; canonical identity identical across independent executions."
  echo "Verdict derivation + recorded-verdict cross-check: replay.sh judge"
  exit 0
}

# --------------------------------------------------- observation extraction --
# extract_defect_fact <cases_root> — sets FACT_PARSE_OK / FACT_CONJ / DEFECT_LIVE.
# Works identically over a live run dir (cmd_run) and the recorded observation
# bundle (cmd_judge); `run`'s byte-identity gate is what makes that sound.
expect_marker() { # expect_marker <file> <fixed-string>
  grep -qF -- "$2" "$1" || { echo "  marker missing: $1 :: $2"; FACT_PARSE_OK=0; }
}
extract_defect_fact() {
  local root="$1" c
  FACT_PARSE_OK=1
  FACT_CONJ=1
  for c in t1_baseline_valid t2_dup_key_then_all_fields t3_all_fields_then_malformed aux_i_dup_key_isolated aux_ii_unknown_field_isolated; do
    expect_marker "$root/$c/stdout.txt" "DECODE_RESULT=OK"
  done
  expect_marker "$root/contrast_t2_value_v100/stdout.txt" "DECODE_RESULT=RAISE"
  expect_marker "$root/contrast_t2_value_v100/stdout.txt" "duplicate table key not allowed: 'a'"
  grep -qF "a_is_second=true" "$root/t2_dup_key_then_all_fields/stdout.txt" || FACT_CONJ=0  # (i) dup key applied
  grep -qF "c_is_empty=true"  "$root/t2_dup_key_then_all_fields/stdout.txt" || FACT_CONJ=0  # (ii) early exit dropped c
  [ "$(cat "$root/t3_all_fields_then_malformed/exit_code.txt")" = "0" ] || FACT_CONJ=0       # (ii) trailing invalid accepted
  grep -qF "a_is_second=true" "$root/aux_i_dup_key_isolated/stdout.txt" || FACT_CONJ=0      # (i) isolated
  grep -qF "b_is_third=false" "$root/aux_i_dup_key_isolated/stdout.txt" || FACT_PARSE_OK=0
  grep -qF "DECODE_RESULT=OK" "$root/aux_ii_unknown_field_isolated/stdout.txt" || FACT_CONJ=0 # (ii) unknown field past fill unexamined
  grep -qF "a=[first]" "$root/t1_baseline_valid/stdout.txt" || FACT_PARSE_OK=0               # baseline sanity
  if [ "$FACT_PARSE_OK" -eq 0 ]; then DEFECT_LIVE="unparseable"
  elif [ "$FACT_CONJ" -eq 1 ]; then DEFECT_LIVE="present"
  else DEFECT_LIVE="absent"; fi
  return 0
}

# ------------------------------------------------------------------ judge ----
rule_row() { awk -F'\t' -v r="$1" '$1==r {print; exit}' "$RULES"; }

rule_row_hash() { # sha256 of the exact rule-table row (line, trailing newline stripped)
  local row
  row="$(rule_row "$1")"
  [ -n "$row" ] || return 1
  printf '%s' "$row" | sha256sum | cut -d' ' -f1
}

derive_verdict() { # derive_verdict <canonical-tuple> — sets DERIVED_VERDICT / DERIVED_RULE (total function)
  local d p c b a rule rl rp rv rb ra verdict
  IFS='|' read -r d p c b a <<< "$1"
  DERIVED_VERDICT="UNKNOWN"
  DERIVED_RULE="DEFAULT"
  while IFS="$(printf '\t')" read -r rule rl rp rv rb ra verdict _summary; do
    case "$rule" in ''|'#'*) continue ;; esac
    if match "$rl" "$d" && match "$rp" "$p" && match "$rv" "$c" && match "$rb" "$b" && match "$ra" "$a"; then
      DERIVED_VERDICT="$verdict"
      DERIVED_RULE="$rule"
      return 0
    fi
  done < "$RULES"
  return 0
}

match() { [ "$1" = "*" ] && return 0; [ "$1" = "$2" ]; }

reason_rules_cited() { # unique R<n>/DEFAULT tokens cited in a reason text (empty if none)
  printf '%s' "$1" | grep -oE '\bR[0-9]+\b|\bDEFAULT\b' 2>/dev/null | LC_ALL=C sort -u | tr '\n' ' '
}

reason_contradicts_verdict() { # reason_contradicts_verdict <reason> <verdict> — 0 = contradiction present
  local reason="$1" verdict="$2" pat
  pat="$(printf '%s' "$verdict" | sed 's/[^A-Za-z0-9]/./g')"
  local re="[Nn][Oo][Tt][[:space:]]+[Aa][[:space:]]+${pat}([^[:alnum:]-]|$)"
  [[ "$reason" =~ $re ]]
}

check_reason_consistency() { # check_reason_consistency <origin-label> <reason> <verdict> <matched-rule>
  local label="$1" reason="$2" verdict="$3" rule="$4" cited
  reason_contradicts_verdict "$reason" "$verdict" && {
    echo "JUDGE: MISMATCH — $label: the reason cell contradicts its own verdict — verdict is $verdict but the reason says it is NOT a $verdict."
    JUDGE_BAD=1
    return 0
  }
  cited="$(reason_rules_cited "$reason")"
  if [ -n "$cited" ]; then
    case " $cited " in
      *" $rule "*) : ;;
      *) echo "JUDGE: MISMATCH — $label: reason cites rule(s) {$(echo "$cited" | tr -s ' ')} but the verdict derives from rule $rule."
         JUDGE_BAD=1 ;;
    esac
  fi
  return 0
}

cmd_judge() {
  echo "== replay judge: pure re-derivation + recorded/ledger cross-check (record is NEVER written) =="
  echo "-- gate: bundle + ledger verification (derivation only over verified bytes)"
  if ! cmd_verify; then
    echo "JUDGE: INVALID — bundle/ledger verification failed; verdicts fail closed (all UNKNOWN)."
    exit 1
  fi

  echo "-- observation tuple (from the recorded observations; run proves live == recorded)"
  extract_defect_fact "$OFFLINE/observations"
  echo "defect_live(B-1 pair)=$DEFECT_LIVE parse_ok=$FACT_PARSE_OK conjunction=$FACT_CONJ"

  # ---- ledger lineage heads: current generation per triple (verify already
  #      guaranteed exactly one per lineage; recompute the mapping here)
  declare -A SUPERSEDED HEAD_EVENT HEAD_PAYLOAD REC_SEEN FACTS_TUPLE
  local ev triple kind at actor eref sup payload lineno=0 line row
  # same tab-remapping as ledger_validate: empty supersedes must survive parsing
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno+1))
    [ "$lineno" = 1 ] && continue
    case "$line" in ''|'#'*) continue ;; esac
    row="${line//$'\t'/$'\x1f'}"
    ev="" triple="" kind="" at="" actor="" eref="" sup="" payload=""
    IFS=$'\x1f' read -r ev triple kind at actor eref sup payload <<< "$row"
    [ -n "$sup" ] && SUPERSEDED[$sup]=1
  done < "$LEDGER"
  lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno+1))
    [ "$lineno" = 1 ] && continue
    case "$line" in ''|'#'*) continue ;; esac
    row="${line//$'\t'/$'\x1f'}"
    ev="" triple="" kind="" at="" actor="" eref="" sup="" payload=""
    IFS=$'\x1f' read -r ev triple kind at actor eref sup payload <<< "$row"
    if [ -z "${SUPERSEDED[$ev]:-}" ]; then
      HEAD_EVENT[$triple]="$ev"
      HEAD_PAYLOAD[$triple]="$payload"
    fi
  done < "$LEDGER"

  # ---- recorded triple set + duplicate detection
  local t v r
  while IFS="$(printf '\t')" read -r t v r; do
    case "$t" in ''|'#'*) continue ;; esac
    if [ -n "${REC_SEEN[$t]:-}" ]; then
      echo "JUDGE: INVALID — duplicate recorded row for triple: $t"
      exit 1
    fi
    REC_SEEN[$t]="$v"
  done < "$RECORDED"

  RUN_DIR="${RUNROOT}/judge_$(date +%Y%m%dT%H%M%S%z)"
  mkdir -p "$RUN_DIR"
  DERIVED_OUT="$RUN_DIR/derived_verdicts.tsv"
  printf 'triple_id\tderived\tmatched_rule\tderived_tuple\trecorded\thead_event\thead_verdict\tresult\n' > "$DERIVED_OUT"

  local all_match=1 JUDGE_BAD=0 d_rec cpath contrast boundary artifact _evidence
  local triple d_live_used d_norm derived_tuple recorded rh hv ht hrid hrh hp_reason rec_reason
  while IFS="$(printf '\t')" read -r triple d_rec cpath contrast boundary artifact _evidence; do
    case "$triple" in ''|'#'*) continue ;; esac
    [ -z "${FACTS_TUPLE[$triple]:-}" ] || { echo "JUDGE: INVALID — duplicate facts row for triple: $triple"; exit 1; }

    d_live_used="$d_rec"
    case "$triple" in
      B-SEC-01*) d_live_used="$DEFECT_LIVE" ;;   # live B-1 fact overrides the recorded defect fact
      *) : ;;                                    # others: pin-level recorded defect fact (not re-runnable offline)
    esac
    d_norm="$(norm_defect "$d_live_used")"
    derived_tuple="$d_norm|$cpath|$contrast|$boundary|$artifact"
    FACTS_TUPLE[$triple]="$derived_tuple"

    # coverage: every facts triple must be recorded
    if [ -z "${REC_SEEN[$triple]:-}" ]; then
      echo "JUDGE: INVALID — facts triple has no recorded verdict in verdicts_recorded.tsv: $triple"
      JUDGE_BAD=1
      continue
    fi

    derive_verdict "$derived_tuple"
    recorded="${REC_SEEN[$triple]}"
    rh="$(rule_row_hash "$DERIVED_RULE")" || { echo "JUDGE: INVALID — matched rule $DERIVED_RULE not found in $RULES (fail-closed)"; JUDGE_BAD=1; rh=""; }

    # coverage: every recorded triple must have a current generation
    if [ -z "${HEAD_EVENT[$triple]:-}" ]; then
      echo "JUDGE: MISMATCH — no current generation in verdict_generations.tsv for recorded triple: $triple"
      JUDGE_BAD=1
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$triple" "$DERIVED_VERDICT" "$DERIVED_RULE" "$derived_tuple" "$recorded" "-" "-" "NO-GENERATION" >> "$DERIVED_OUT"
      continue
    fi

    hv="$(pf "${HEAD_PAYLOAD[$triple]}" '.verdict')"
    ht="$(tuple_canonical "$(pf "${HEAD_PAYLOAD[$triple]}" '.tuple')")"
    hrid="$(pf "${HEAD_PAYLOAD[$triple]}" '.rule_id')"
    hrh="$(pf "${HEAD_PAYLOAD[$triple]}" '.rule_hash')"
    hp_reason="$(pf "${HEAD_PAYLOAD[$triple]}" '.reason')"
    rec_reason="$(awk -F'\t' -v t="$triple" '$1==t {print $3; exit}' "$RECORDED")"

    local row_ok=1
    [ "$hv" = "$DERIVED_VERDICT" ] || { echo "JUDGE: MISMATCH — $triple: generation ${HEAD_EVENT[$triple]} verdict '$hv' != derived '$DERIVED_VERDICT' (rule $DERIVED_RULE)"; row_ok=0; }
    [ "$ht" = "$derived_tuple" ] || { echo "JUDGE: MISMATCH — $triple: generation ${HEAD_EVENT[$triple]} tuple '$ht' != derived tuple '$derived_tuple'"; row_ok=0; }
    [ "$hrid" = "$DERIVED_RULE" ] || { echo "JUDGE: MISMATCH — $triple: generation ${HEAD_EVENT[$triple]} rule_id '$hrid' != matched rule '$DERIVED_RULE'"; row_ok=0; }
    if [ -n "$rh" ] && [ "$hrh" != "$rh" ]; then
      echo "JUDGE: MISMATCH — $triple: generation ${HEAD_EVENT[$triple]} rule_hash '$hrh' != sha256 of rule-table row $DERIVED_RULE ('$rh') — rule basis changed since recording, or payload corrupt."
      row_ok=0
    fi
    [ "$hv" = "$recorded" ] || { echo "JUDGE: MISMATCH — $triple: ledger head verdict '$hv' != verdicts_recorded.tsv '$recorded'"; row_ok=0; }
    # recorded reason cells are a projection of the ledger head payload — byte equality is the binding invariant
    [ "$rec_reason" = "$hp_reason" ] || { echo "JUDGE: MISMATCH — $triple: recorded reason != ledger head payload.reason (projection divergence)"; row_ok=0; }

    # reason cells (ledger payload AND recorded TSV) must not contradict the verdict
    check_reason_consistency "$triple generation ${HEAD_EVENT[$triple]} payload.reason" "$hp_reason" "$DERIVED_VERDICT" "$DERIVED_RULE"
    check_reason_consistency "$triple verdicts_recorded.tsv reason" "$rec_reason" "$DERIVED_VERDICT" "$DERIVED_RULE"

    [ "$row_ok" = 1 ] || JUDGE_BAD=1
    local result="MATCH"; [ "$row_ok" = 1 ] && [ "$DERIVED_VERDICT" = "$recorded" ] || result="MISMATCH"
    if [ "$result" = "MISMATCH" ] && [ "$DERIVED_VERDICT" != "$recorded" ]; then
      echo "JUDGE: MISMATCH — $triple: derived '$DERIVED_VERDICT' != recorded '$recorded'"
    fi
    [ "$result" = "MATCH" ] || all_match=0
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$triple" "$DERIVED_VERDICT" "$DERIVED_RULE" "$derived_tuple" "$recorded" "${HEAD_EVENT[$triple]}" "$hv" "$result" >> "$DERIVED_OUT"
    printf '  %-55s derived=%-8s (rule %-7s) recorded=%-8s head=%s:%-8s %s\n' "$triple" "$DERIVED_VERDICT" "$DERIVED_RULE" "$recorded" "${HEAD_EVENT[$triple]}" "$hv" "$result"
  done < <(grep -v '^#' "$FACTS")

  # coverage the other way: recorded triples without observation facts rows
  for t in "${!REC_SEEN[@]}"; do
    if [ -z "${FACTS_TUPLE[$t]:-}" ]; then
      echo "JUDGE: INVALID — recorded triple has no observation facts row (not re-derivable): $t"
      JUDGE_BAD=1
    elif [ -z "${HEAD_EVENT[$t]:-}" ]; then
      : # already reported in the main loop
    fi
  done
  # ledger lineages for triples that are not recorded at all
  for t in "${!HEAD_EVENT[@]}"; do
    [ -z "${REC_SEEN[$t]:-}" ] && { echo "JUDGE: MISMATCH — ledger lineage for unrecorded triple: $t"; JUDGE_BAD=1; }
  done

  echo "-- verdict semantics reminder (rules/rule_table.tsv header is binding)"
  echo "   NO-GO is a SCOPED verdict (tested scope only, NOT ecosystem safety);"
  echo "   UNKNOWN = insufficiently established, never 'safe'."
  echo "derived table (temporary location, record untouched): $DERIVED_OUT"

  if [ "$JUDGE_BAD" -eq 0 ] && [ "$all_match" -eq 1 ]; then
    echo "JUDGE: PASS — re-derived verdicts equal the recorded verdicts AND the current generation of every lineage."
    exit 0
  fi
  echo "JUDGE: MISMATCH — the record is broken (recorded values, ledger generations, or reason cells disagree with the pure re-derivation)."
  echo "        The record is NEVER auto-corrected; fix the record or re-evaluate."
  exit 1
}

# -------------------------------------------------------------- freshness ----
cmd_freshness() {
  local fired=0
  FIRED=()
  fire() { fired=1; FIRED+=("$1"); echo "  TERM FIRED : $1 — $2"; }
  affirm() { echo "  TERM FRESH : $1 — $2"; }
  snap_value() { awk -F'\t' -v f="$1" -v s="$2" '$1==f && $2==s {print $3; exit}' "$SNAPSHOT"; }

  echo "== freshness evaluation (baseline = judgment-time snapshot; READ-ONLY, no logs written) =="

  # ---- term 1: subject HEAD
  local recorded_subject current_subject cpath current how repo value consumer consumer_commit field scope evidence
  recorded_subject="$(snap_value subject_head subject)"
  current_subject="$(git -C "$SUBJECT" rev-parse HEAD 2>/dev/null)"
  if [ -z "$recorded_subject" ]; then
    fire "subject_head" "no recorded subject head in snapshot (undefined -> fail-closed)"
  elif [ -z "$current_subject" ]; then
    fire "subject_head" "current subject HEAD unavailable at $SUBJECT"
  elif [ "$recorded_subject" != "$current_subject" ]; then
    fire "subject_head" "recorded=$recorded_subject current=$current_subject"
  else
    affirm "subject_head" "recorded == current == $current_subject"
  fi

  # ---- term 2: consumer commits (per consumer)
  while IFS="$(printf '\t')" read -r field scope value evidence; do
    [ "$field" = "consumer_commit" ] || continue
    consumer="$scope"
    if [ "$value" = "UNRECORDED" ] || [ -z "$value" ]; then
      fire "consumer_commit[$consumer]" "consumer commit was never pinned at judgment time; cannot affirm the world did not move"
      continue
    fi
    cpath="$(snap_value consumer_path "$consumer")"
    current=""
    how=""
    if [ -n "$cpath" ] && [ -d "$cpath/.git" ]; then
      current="$(git -C "$cpath" rev-parse HEAD 2>/dev/null)"; how="local-checkout"
    else
      # Freshness is about the EXTERNAL world, so an offline-only view is not
      # sufficient by design. Fall back to a read-only remote query (git ls-remote)
      # against the recorded upstream repo. Reproduction stays offline; freshness
      # observes the outside. Fail closed only when neither view is available.
      repo="$(snap_value consumer_repo "$consumer")"
      if [ -n "$repo" ] && [ "$repo" != "UNRECORDED" ]; then
        current="$(git ls-remote "$repo" HEAD 2>/dev/null | awk '{print $1; exit}')"; how="ls-remote:$repo"
      fi
    fi
    if [ -z "$current" ]; then
      fire "consumer_commit[$consumer]" "recorded=$value but current commit undeterminable (no usable local checkout at ${cpath:-<none>} and no consumer_repo for a remote query)"
    elif [ "$current" != "$value" ]; then
      fire "consumer_commit[$consumer]" "recorded=$value current=$current ($how)"
    else
      affirm "consumer_commit[$consumer]" "recorded == current == $value ($how)"
    fi
  done < <(awk -F'\t' '$1 !~ /^#/ {print}' "$SNAPSHOT")

  # ---- term 3: resolved dependency hashes (per consumer dependency)
  while IFS="$(printf '\t')" read -r field scope value evidence; do
    [ "$field" = "consumer_dep_commit" ] || continue
    consumer="${scope%%→*}"
    if [ "$value" = "UNRESOLVED" ] || [ "$value" = "UNRECORDED" ] || [ -z "$value" ]; then
      fire "dep_hash[$scope]" "dependency identity unresolved/unrecorded at judgment time (declared version ranges are not identities)"
      continue
    fi
    # A recorded dep commit is affirmable only if the consumer that resolves it is
    # itself affirmable (term 2 fresh) AND the pinned object still exists.
    consumer_commit="$(snap_value consumer_commit "$consumer")"
    if [ "$consumer_commit" = "UNRECORDED" ] || [ -z "$consumer_commit" ]; then
      fire "dep_hash[$scope]" "dep pin recorded ($value) but consumer commit unpinned -> current resolution undeterminable"
      continue
    fi
    if ! git -C "$SUBJECT" cat-file -e "${value}^{commit}" 2>/dev/null; then
      fire "dep_hash[$scope]" "pinned dep commit object no longer resolvable in subject repo: $value"
      continue
    fi
    affirm "dep_hash[$scope]" "pin object resolvable; consumer commit fresh -> dep identity holds ($value)"
  done < <(awk -F'\t' '$1 !~ /^#/ {print}' "$SNAPSHOT")

  # ---- term 4: vendored dep bundle integrity (= replay.sh verify)
  echo "  verifying vendored dep bundle integrity (MANIFEST + ledger)..."
  if ! ( cmd_verify ) >/dev/null 2>&1; then
    fire "dep_hash[library-slice]" "MANIFEST/ledger verification FAILED (vendored deps or records mutated)"
  else
    affirm "dep_hash[library-slice]" "vendored bundle matches MANIFEST ($(grep -vc '^#' "$MANIFEST") entries); ledger chain valid"
  fi

  echo "== result =="
  if [ "$fired" -ne 0 ]; then
    echo "RE-EVALUATE REQUIRED"
    echo "fired terms: ${FIRED[*]}"
    echo "The recorded verdicts are historical records; they MUST NOT be treated as current until re-evaluation."
    exit 1
  fi
  echo "FRESH — predicate not fired: recorded snapshot matches the current world on all terms."
  exit 0
}

# --------------------------------------------------------------- dispatch ----
case "${1:-}" in
  verify)    cmd_verify;    exit $? ;;
  run)       cmd_run ;;
  judge)     cmd_judge ;;
  freshness) cmd_freshness ;;
  *)
    echo "usage: replay.sh {verify|run|judge|freshness}"
    echo "  verify    — READ-ONLY: MANIFEST hashes + ledger chain + reference integrity + subject blobs"
    echo "  run       — replay the pinned snapshot: build, 7 cases x2 executions, raw + canonical byte-identity"
    echo "  judge     — pure re-derivation vs verdicts_recorded.tsv and verdict_generations.tsv heads (fail-closed)"
    echo "  freshness — READ-ONLY: FRESH / RE-EVALUATE vs the judgment-time snapshot"
    exit 1
    ;;
esac
