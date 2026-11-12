#!/usr/bin/env bash
# Org-required-workflow run 관측 래퍼 — `gh run view/watch <id>`는 org required
# workflow 런에서 workflow_id 해석 404가 난다 (docs/spec/gh_org_required_workflow_run_quirks.md
# "Sanctioned workarounds" 2번: raw REST GET /repos/{owner}/{repo}/actions/runs/{id}).
# 용법: run_view.sh <run_id> [jobs]
set -euo pipefail
id="${1:?usage: run_view.sh <run_id> [jobs]}"
gh api "repos/${AXIOM_REPO:-Archright/Axiom}/actions/runs/$id" --jq '{id,name,path,event,conclusion,run_attempt}'
if [ "${2:-}" = jobs ]; then
  gh api "repos/${AXIOM_REPO:-Archright/Axiom}/actions/runs/$id/jobs" --jq '.jobs[]|"\(.name)=\(.conclusion)"'
fi
