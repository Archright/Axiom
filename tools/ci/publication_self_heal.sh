#!/usr/bin/env bash
# publication_self_heal.sh — Publication hygiene audit, artifact/log purge, and
# GitHub Support dereferencing bundle generator.
#
# Supported modes:
#   --audit-refs               Fetch refs/heads/*, refs/tags/*, and refs/pull/*/head
#                              into an isolated temp workspace and run gitleaks
#                              (--redact=100) over the declared publication surface
#                              (security-policy.yml secretScan.historyScopeLogOpts:
#                              origin/main + HEAD + refs/pull/*/head) +
#                              publication_provenance_validator. Closed/unmerged
#                              PR refs are inside that surface: their findings are
#                              publication findings, not a separate isolated lane.
#   --purge-run-logs <run_id>  Delete workflow run logs via GitHub REST API:
#                              gh api -X DELETE repos/<owner>/<repo>/actions/runs/<run_id>/logs
#   --purge-leaky-artifacts    Enumerate non-expired workflow artifacts (specifically
#                              raw secret-scan/gitleaks artifacts or a targeted
#                              --run-id <id>) and delete them via GitHub REST API:
#                              gh api -X DELETE repos/<owner>/<repo>/actions/artifacts/<artifact_id>
#   --support-bundle           Audit unmerged PR refs (refs/pull/*/head) and emit
#                              a ready-to-submit GitHub Support request to
#                              dereference polluted PR refs and run server-side GC.
#
# Options:
#   --dry-run                  Print API mutations / actions without executing them.
#   --repo <owner/repo>        Explicit GitHub repository slug (defaults to
#                              GITHUB_REPOSITORY / GH_REPO / origin remote).
#   --run-id <run_id>          Optional run ID filter for --purge-leaky-artifacts.
#   --out <path>               Optional output path for --support-bundle.
#   -h, --help                 Show this help text and exit 0.

set -euo pipefail

DRY_RUN=0
REPO_OVERRIDE=""
MODE_AUDIT_REFS=0
PURGE_RUN_ID=""
MODE_PURGE_ARTIFACTS=0
FILTER_RUN_ID=""
MODE_SUPPORT_BUNDLE=0
BUNDLE_OUT=""

usage() {
  cat <<'EOF'
Usage: tools/ci/publication_self_heal.sh [OPTIONS]

Modes (one or more):
  --audit-refs                 Audit the declared publication surface (origin/main +
                               HEAD + refs/pull/*/head — security-policy.yml
                               secretScan.historyScopeLogOpts) in an isolated
                               temporary git workspace using gitleaks (--redact=100)
                               and publication_provenance_validator.
  --purge-run-logs <run_id>    Delete GitHub Actions logs for <run_id> via
                               gh api -X DELETE repos/<owner>/<repo>/actions/runs/<run_id>/logs
  --purge-leaky-artifacts      Delete leaky / raw secret-scan workflow artifacts via
                               gh api -X DELETE repos/<owner>/<repo>/actions/artifacts/<id>
  --support-bundle             Generate a ready-to-submit GitHub Support ticket payload
                               listing exact refs/pull/<N>/head refs and commit SHAs
                               requiring server-side dereferencing and GC.

Options:
  --dry-run                    Print destructive commands without executing them.
  --repo <owner/repo>          Override target GitHub repository (owner/repo).
  --run-id <run_id>            Scope --purge-leaky-artifacts to a single workflow run.
  --out <path>                 Write --support-bundle output to <path> instead of stdout.
  -h, --help                   Show this help message and exit.
EOF
}

if [ "$#" -eq 0 ]; then
  usage
  exit 0
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --repo)
      [ "$#" -ge 2 ] || { echo "ERROR: --repo requires <owner/repo>" >&2; exit 2; }
      REPO_OVERRIDE="$2"
      shift 2
      ;;
    --audit-refs)
      MODE_AUDIT_REFS=1
      shift
      ;;
    --purge-run-logs)
      [ "$#" -ge 2 ] || { echo "ERROR: --purge-run-logs requires <run_id>" >&2; exit 2; }
      PURGE_RUN_ID="$2"
      shift 2
      ;;
    --purge-leaky-artifacts)
      MODE_PURGE_ARTIFACTS=1
      shift
      ;;
    --run-id)
      [ "$#" -ge 2 ] || { echo "ERROR: --run-id requires <run_id>" >&2; exit 2; }
      FILTER_RUN_ID="$2"
      shift 2
      ;;
    --support-bundle)
      MODE_SUPPORT_BUNDLE=1
      shift
      ;;
    --out)
      [ "$#" -ge 2 ] || { echo "ERROR: --out requires <path>" >&2; exit 2; }
      BUNDLE_OUT="$2"
      shift 2
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

resolve_repo() {
  if [ -n "$REPO_OVERRIDE" ]; then
    printf '%s\n' "$REPO_OVERRIDE"
    return 0
  fi
  if [ -n "${GH_REPO:-}" ]; then
    printf '%s\n' "$GH_REPO"
    return 0
  fi
  if [ -n "${GITHUB_REPOSITORY:-}" ]; then
    printf '%s\n' "$GITHUB_REPOSITORY"
    return 0
  fi
  local url
  url="$(git config --get remote.origin.url 2>/dev/null || true)"
  if [ -n "$url" ]; then
    url="${url%.git}"
    case "$url" in
      https://github.com/*)
        printf '%s\n' "${url#https://github.com/}"
        return 0
        ;;
      git@github.com:*)
        printf '%s\n' "${url#git@github.com:}"
        return 0
        ;;
    esac
  fi
  if command -v gh >/dev/null 2>&1; then
    gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null && return 0
  fi
  echo "ERROR: could not determine <owner/repo>; pass --repo <owner/repo>" >&2
  return 1
}

ensure_gitleaks() {
  local workdir="$1"
  if command -v gitleaks >/dev/null 2>&1; then
    command -v gitleaks
    return 0
  fi
  local url="https://github.com/gitleaks/gitleaks/releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz"
  local expected="551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb"
  mkdir -p "$workdir/gitleaks-bin"
  curl -fsSL --retry 3 -o "$workdir/gitleaks.tar.gz" "$url"
  printf '%s  %s\n' "$expected" "$workdir/gitleaks.tar.gz" | sha256sum -c - >/dev/null
  tar -xzf "$workdir/gitleaks.tar.gz" -C "$workdir/gitleaks-bin"
  printf '%s\n' "$workdir/gitleaks-bin/gitleaks"
}

run_audit_refs() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Would create isolated temp git workspace from $repo_root"
    echo "[dry-run] Would fetch +refs/heads/*:refs/remotes/origin/* +refs/tags/*:refs/tags/* +refs/pull/*/head:refs/remotes/pr/*"
    echo "[dry-run] Would run gitleaks git --redact=100 on the declared publication surface (--log-opts 'origin/main HEAD --glob=refs/remotes/pr/*' — security-policy.yml secretScan.historyScopeLogOpts)"
    echo "[dry-run] Would compile and run tools/ci/publication_provenance_validator.nim on HEAD"
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  echo "[audit-refs] Initializing isolated git workspace in $tmpdir..."
  git clone --quiet --no-local "$repo_root" "$tmpdir/repo"
  local remote_url
  remote_url="$(git -C "$repo_root" config --get remote.origin.url || true)"
  if [ -n "$remote_url" ]; then
    git -C "$tmpdir/repo" remote set-url origin "$remote_url"
    git -C "$tmpdir/repo" fetch --quiet --no-tags --prune origin \
      '+refs/heads/*:refs/remotes/origin/*' \
      '+refs/tags/*:refs/tags/*' \
      '+refs/pull/*/head:refs/remotes/pr/*' || true
  fi

  local gl_bin
  gl_bin="$(ensure_gitleaks "$tmpdir")"

  echo "[audit-refs] Scanning the declared publication surface (origin/main + HEAD + refs/pull/*/head) with --redact=100..."
  # SSOT: compliance/policy/security-policy.yml secretScan.historyScopeLogOpts —
  # the same scope the publication-integrity secret-scan job scans, so this local
  # audit and CI adjudicate the SAME commit set. The former wider surface
  # (--branches --tags --remotes=origin HEAD) reached out-of-tree evidence ledgers
  # whose fresh 64-hex CAS evidenceKeys are false positives no static baseline can
  # contain, and the former second lane (--glob=refs/remotes/pr/* --not ...) only
  # recomputed a subset of this scope: refs/pull/*/head are positive revisions of
  # the declared scope (duplicated-lane anti-pattern, retired in the workflow's
  # secret-scan 2026-11-13).
  "$gl_bin" git \
    --redact=100 \
    --log-opts "origin/main HEAD --glob=refs/remotes/pr/*" \
    --report-format json \
    --report-path "$tmpdir/pub_history.json" \
    --no-banner --exit-code 1 "$tmpdir/repo" || true
  local pub_count=0
  if [ -s "$tmpdir/pub_history.json" ]; then
    pub_count="$(jq 'length' "$tmpdir/pub_history.json")"
  fi
  echo "[audit-refs] Publication surface findings (redacted): $pub_count"

  echo "[audit-refs] Running publication_provenance_validator on working tree..."
  nim c --hints:off --warnings:off --skipParentCfg --skipProjCfg --path:"$repo_root" --path:"$repo_root/src" \
    --nimcache:"$tmpdir/nimcache" \
    -o:"$tmpdir/vsi_provenance" "$repo_root/tools/ci/publication_provenance_validator.nim"
  "$tmpdir/vsi_provenance" --repo-root "$repo_root" --out "$tmpdir/provenance_report.json"
}

run_purge_run_logs() {
  local run_id="$1"
  local repo
  repo="$(resolve_repo)"
  local endpoint="repos/${repo}/actions/runs/${run_id}/logs"
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] gh api -X DELETE \"$endpoint\""
    return 0
  fi
  echo "[purge-run-logs] Deleting logs for run $run_id in $repo..."
  gh api -X DELETE "$endpoint"
  echo "[purge-run-logs] Deleted logs for run $run_id."
}

run_purge_leaky_artifacts() {
  local repo
  repo="$(resolve_repo)"
  local list_endpoint
  if [ -n "$FILTER_RUN_ID" ]; then
    list_endpoint="repos/${repo}/actions/runs/${FILTER_RUN_ID}/artifacts?per_page=100"
  else
    list_endpoint="repos/${repo}/actions/artifacts?per_page=100"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "[dry-run] Would query non-expired artifacts from: gh api --paginate \"$list_endpoint\""
    echo "[dry-run] Would delete matching leaky artifacts (publication-report-secret-scan / gitleaks*) via:"
    echo "[dry-run]   gh api -X DELETE \"repos/${repo}/actions/artifacts/<artifact_id>\""
    return 0
  fi

  echo "[purge-leaky-artifacts] Listing non-expired artifacts from $list_endpoint..."
  local ids
  ids="$(gh api --paginate "$list_endpoint" \
    --jq '.artifacts[] | select(.expired == false and (.name == "publication-report-secret-scan" or (.name | test("gitleaks"; "i")))) | "\(.id)\t\(.name)\t\(.workflow_run.id // 0)"')"
  if [ -z "$ids" ]; then
    echo "[purge-leaky-artifacts] No matching non-expired leaky artifacts found."
    return 0
  fi
  while IFS=$'\t' read -r art_id art_name wf_run_id; do
    [ -n "$art_id" ] || continue
    echo "[purge-leaky-artifacts] Deleting artifact id=$art_id name=$art_name (run=$wf_run_id)..."
    gh api -X DELETE "repos/${repo}/actions/artifacts/${art_id}"
  done <<< "$ids"
}

run_support_bundle() {
  local repo
  repo="$(resolve_repo)"
  local repo_root
  repo_root="$(git rev-parse --show-toplevel)"
  local polluted_lines=""

  if [ "$DRY_RUN" -eq 0 ]; then
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' RETURN
    git clone --quiet --no-local "$repo_root" "$tmpdir/repo"
    local remote_url
    remote_url="$(git -C "$repo_root" config --get remote.origin.url || true)"
    if [ -n "$remote_url" ]; then
      git -C "$tmpdir/repo" remote set-url origin "$remote_url"
      git -C "$tmpdir/repo" fetch --quiet --no-tags --prune origin \
        '+refs/heads/*:refs/remotes/origin/*' \
        '+refs/tags/*:refs/tags/*' \
        '+refs/pull/*/head:refs/remotes/pr/*' || true
    fi
    if git -C "$tmpdir/repo" for-each-ref --format='%(refname)' refs/remotes/pr/ | grep -q .; then
      local gl_bin
      gl_bin="$(ensure_gitleaks "$tmpdir")"
      "$gl_bin" git \
        --redact=100 \
        --log-opts "--glob=refs/remotes/pr/* --not --branches --tags --remotes=origin" \
        --report-format json \
        --report-path "$tmpdir/pr_history.json" \
        --no-banner --exit-code 1 "$tmpdir/repo" || true
      if [ -s "$tmpdir/pr_history.json" ]; then
        while IFS=' ' read -r ref sha; do
          local hits
          hits="$(jq --arg s "$sha" '[.[] | select(.Commit == $s)] | length' "$tmpdir/pr_history.json")"
          if [ "${hits:-0}" -gt 0 ]; then
            local pr_num="${ref#refs/remotes/pr/}"
            polluted_lines="${polluted_lines}- Ref: refs/pull/${pr_num}/head | Commit SHA: ${sha} (${hits} redacted finding(s))"$'\n'
          fi
        done < <(git -C "$tmpdir/repo" for-each-ref --format='%(refname) %(objectname)' refs/remotes/pr/)
      fi
    fi
  fi

  if [ -z "$polluted_lines" ]; then
    polluted_lines="- Ref: refs/pull/<PR_NUMBER>/head | Commit SHA: <COMMIT_SHA> (populate via --audit-refs against live origin)"$'\n'
  fi

  local payload
  payload="$(cat <<EOF
Subject: Request to dereference closed PR refs and run server-side GC on ${repo}

Hello GitHub Support,

We are preparing the repository https://github.com/${repo} for public release.
Please dereference the following unmerged/closed pull request refs and run a
server-side garbage collection (git gc / prune) to purge unreachable commit
objects from the repository object store and fork network cache:

Repository: ${repo}
Target refs and commit SHAs to dereference and purge:
${polluted_lines}
Confirmations:
1. The commits above are NOT reachable from any branch (refs/heads/*) or tag (refs/tags/*).
2. Any affected credentials have already been revoked/rotated.
3. Workflow run logs and artifacts referencing those commits have been purged via the Actions REST API.

Thank you!
EOF
)"

  if [ -n "$BUNDLE_OUT" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      echo "[dry-run] Would write support bundle to $BUNDLE_OUT"
      printf '%s\n' "$payload"
    else
      printf '%s\n' "$payload" > "$BUNDLE_OUT"
      echo "[support-bundle] Wrote support request bundle to $BUNDLE_OUT"
    fi
  else
    printf '%s\n' "$payload"
  fi
}

if [ "$MODE_AUDIT_REFS" -eq 1 ]; then
  run_audit_refs
fi

if [ -n "$PURGE_RUN_ID" ]; then
  run_purge_run_logs "$PURGE_RUN_ID"
fi

if [ "$MODE_PURGE_ARTIFACTS" -eq 1 ]; then
  run_purge_leaky_artifacts
fi

if [ "$MODE_SUPPORT_BUNDLE" -eq 1 ]; then
  run_support_bundle
fi
