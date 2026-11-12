import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}

## Landing CLI — thin actuator — `ax landing` (ADR-0025 Amendment A,
## plan rev.7 Phase 0).
##
## The landing actuation is a SINGLE GitHub native MERGE —
## `PUT /pulls/{n}/merge` (merge_method=merge, sha=headSha — HEAD PIN only).
## The CLI performs NO merge computation, NO ref mutation, NO local
## merge-tree construction and NO self-CAS: the platform ruleset (strict +
## required status check `admission-check`) is the base-binding enforcement
## at merge evaluation. Self-owned merge authority = 0 (E1).
##
##   1. verify certificate   — Ed25519 attestation + EXACT (B, H) binding
##      (reuses verifyCertificateAttestation + chain-reuses Pass 2.96 /
##      verifyContinuity; no reimplementation).
##   2. A3 preflight          — compare(B...H).status == "ahead" (H ⊇ B, so
##      GitHub's merge commit carries tree(M) == tree(H) == certTree —
##      invariant 7). Any other relation (behind/identical/diverged) aborts
##      fail-closed. Base freshness itself is GitHub's ruleset strict at
##      merge time (tip==B observation removed — platform delegation).
##   3. required checks       — GitHub's ruleset (required check
##      `admission-check` + strict) enforces at merge evaluation; the A2
##      ruleset re-derivation was removed (P12 delegation).
##   4. actuation             — PUT /pulls/{n}/merge (merge_method=merge,
##      sha=H). Base binding = A1 actuator identity ∉ effective bypass
##      actors + ruleset strict at merge evaluation; A3 is preflight only.
##   5. post-merge observation — merge-commit shape + verifyContinuity(M):
##      audit ONLY (A4 / invariant 8) — never landing authority; the
##      landing already happened. Observation mismatch = fail-visible
##      backstop.
##   6. journal               — landing audit record (.axiom/gate_history).
##
## Token/actuator identity (A1): the actuation uses GITHUB_TOKEN (env) —
## the Landing App installation token is NOT used. The invariant
## `landing actuator identity ∉ effective bypass actors` is enforced by the
## ruleset bypass-actors list (live-observed empty on the production main
## ruleset, canonical_run_graph.md D1); this CLI documents and pre-flights
## it but cannot rewrite platform bypass config.
##
## Machine interface:
##   stdout:  LANDING_REQUEST {json}   (issued before any mutation)
##   stdout:  LANDING_OK {"mergeSha": <M>, "tempRefUsed": ""}
##   stderr:  LANDING_FAIL {"reasonCode": <code>, "reason": <text>}

import std/[os, json, strutils]
import core/axiom_pragmas
import core/results
import core/parsers/safe_parsers
import infrastructure/logging_facade
import infrastructure/certificate_attestation
import verification/continuity_check
import cli/merge_cli

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  ## The signed landing request — {B, H, cert_ref} emitted before any
  ## mutation and journaled afterwards. Identity is (B, H), never M.
  LandingRequest* = object
    baseSha*: string        ## B — expected main SHA
    headSha*: string        ## H — certified PR head SHA
    certRef*: string        ## certificate source: ledger:<B>:<H> or a file path
    prNumber*: int          ## PR number — REQUIRED for native merge actuation
    prHeadRef*: string      ## PR head ref (message convention), "" if unknown

  LandingResult* = object
    mergeSha*: string       ## M — the server-created merge commit OID
    tempRefUsed*: string    ## retained for interface stability (always "")

  LandingFailure* = object
    reasonCode*: string
    reason*: string

func landingFailure(code, reason: string): LandingFailure {.raises: [].} =
  LandingFailure(reasonCode: code, reason: reason)

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

func isOid40(s: string): bool {.raises: [].} =
  ## Lowercase 40-hex git object id grammar (same grammar as the continuity
  ## predicate; duplicated here so the landing layer never depends on an
  ## I/O-boundary-only module for its ref grammar).
  if s.len != 40:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true

func landingRequestJson*(req: LandingRequest): string {.raises: [].} =
  ## Canonical machine-readable landing request (the "signed landing request"
  ## emission; signing happens via the certificate's Ed25519 attestation).
  $ %*{
    "B": req.baseSha,
    "H": req.headSha,
    "certRef": req.certRef,
    "prNumber": req.prNumber
  }

func verifyCertBinding*(cert: JsonNode; baseSha, headSha: string): string {.raises: [].} =
  ## Landing step 1 (pure part) — the certificate must be a valid
  ## subject-continuity certificate (Ed25519 attestation) whose baseSha and
  ## headSha EQUAL the landing request's B and H EXACTLY. Missing ≠ valid
  ## empty; any mismatch returns a non-empty reason ("" = bound).
  if cert.isNil or cert.kind != JObject:
    return "no certificate bound to the landing request (fail-closed)"
  if cert.getOrDefault("kind").getStr("") != "subject-continuity":
    return "certificate kind != subject-continuity (fail-closed)"
  if not verifyCertificateAttestation(cert).isOk:
    return "certificate Ed25519 attestation invalid (fail-closed)"
  let certBase = cert.getOrDefault("baseSha").getStr("")
  let certHead = cert.getOrDefault("headSha").getStr("")
  if certBase != baseSha:
    return "certificate baseSha " & certBase[0 ..< min(certBase.len, 12)] &
      " != landing B " & baseSha[0 ..< min(baseSha.len, 12)] &
      " — certificate is for a different base (re-attest)"
  if certHead != headSha:
    return "certificate headSha " & certHead[0 ..< min(certHead.len, 12)] &
      " != landing H " & headSha[0 ..< min(headSha.len, 12)] &
      " — certificate is for a different head (re-attest)"
  ""

proc verifyCertEnvDigests(cert: JsonNode): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## INV-1 C1 env conjuncts (mirror of Pass 2.96 POLICY_MISMATCH /
  ## SCOPE_MISMATCH): the certificate's policyDigest/scopeDigest must equal
  ## the CURRENT tracked files. "" = bound. Digest computation matches
  ## continuity_check's fileSha256Hex convention (CWD-relative).
  let policyNow = fileSha256Hex("config/policy/merge_admission.json")
  let scopeNow = fileSha256Hex("data/verification_scope.lock")
  if policyNow.len == 0 or scopeNow.len == 0:
    return "environment digest computation failed (fail-closed)"
  let certPolicy = cert.getOrDefault("policyDigest").getStr("")
  let certScope = cert.getOrDefault("scopeDigest").getStr("")
  if certPolicy != policyNow:
    return "certificate policyDigest != current sha256(config/policy/merge_admission.json) (re-attest under the current policy)"
  if certScope != scopeNow:
    return "certificate scopeDigest != current sha256(data/verification_scope.lock) (re-attest under the current verification scope)"
  ""

# ---------------------------------------------------------------------------
# I/O — GitHub API reads (rest of the helpers live in cli/merge_cli)
# ---------------------------------------------------------------------------

proc fetchPrHead*(prNumber: int; token, repo: string): Result[string, LandingFailure]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## PR head SHA via GET /pulls/{N} — the PR-identity read for --pr mode.
  try:
    let j = ghGet("https://api.github.com/repos/" & repo & "/pulls/" & $prNumber, token)
    let headSha = j.getOrDefault("head").getOrDefault("sha").getStr("")
    let baseRef = j.getOrDefault("base").getOrDefault("ref").getStr("")
    if not isOid40(headSha):
      return err(landingFailure("PR_HEAD_UNRESOLVABLE",
        "PR " & $prNumber & " head sha unresolvable (fail-closed)"))
    if baseRef != "main":
      return err(landingFailure("PR_BASE_MOVED",
        "PR " & $prNumber & " base.ref '" & baseRef & "' != main (base moved — new admission needed)"))
    ok(headSha)
  except CatchableError as e:
    err(landingFailure("PR_FETCH_FAILED", "GET pulls/" & $prNumber & " failed: " & e.msg))

proc compareStatus*(baseSha, headSha, token, repo: string): Result[tuple[status: string, aheadBy, behindBy: int], LandingFailure]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## A3 preflight read (invariant 7) — GET /compare/{B}...{H} (three-dot):
  ## the relation must be "ahead" (H ⊇ B) so GitHub's native merge commit
  ## carries tree(M) == tree(H) == certTree. behind/identical/diverged abort
  ## (fail-closed abort, never a silent pass-through — no local merge-tree
  ## construction and no /merges resolution path exists anymore).
  try:
    let j = ghGet("https://api.github.com/repos/" & repo & "/compare/" & baseSha & "..." & headSha, token)
    let status = j.getOrDefault("status").getStr("")
    if status.len == 0:
      return err(landingFailure("COMPARE_FAILED",
        "compare(B...H) returned no status (fail-closed)"))
    ok((status: status, aheadBy: j.getOrDefault("ahead_by").getInt(),
       behindBy: j.getOrDefault("behind_by").getInt()))
  except CatchableError as e:
    err(landingFailure("COMPARE_FAILED", "GET compare failed: " & e.msg))

proc observePrState(prNumber: int; token, repo: string): string
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Step 6 bookkeeping observation (never a gate): how does GitHub see the
  ## PR after the CAS landing? GitHub-native merge detection decides
  ## open/closed/merged — the CLI has no pull-requests:write and never
  ## mutates PR state.
  if prNumber <= 0:
    return "n/a"
  try:
    let j = ghGet("https://api.github.com/repos/" & repo & "/pulls/" & $prNumber, token)
    let state = j.getOrDefault("state").getStr("")
    let merged = j.getOrDefault("merged").getBool()
    if merged:
      "merged (GitHub-native detection)"
    elif state == "closed":
      "closed (GitHub-native detection)"
    elif state == "open":
      "open (GitHub-native detection pending)"
    else:
      "unresolvable"
  except CatchableError:
    "unresolvable (observation failed)"

proc recordLanding(req: LandingRequest; res: LandingResult; tempRef: string; outcome, reasonCode, reason, token, repo: string): bool
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Step 6 journaling — the landing audit record (append-only gate history,
  ## same substrate as merge-publish). false = journal write failed
  ## (fail-closed: a landing without an audit record is not reported as done).
  try:
    let entry = %*{
      "stage": "landing-publish",
      "timestamp": getTimestamp(),
      "prNumber": req.prNumber,
      "baseSha": req.baseSha,
      "headSha": req.headSha,
      "certRef": req.certRef,
      "mergeCommitSha": res.mergeSha,
      "tempRef": tempRef,
      "outcome": outcome,
      "reasonCode": reasonCode,
      "reason": reason,
      "prStateAfter": observePrState(req.prNumber, token, repo)}
    appendGateHistory($entry)
    true
  except CatchableError:
    false

# ---------------------------------------------------------------------------
# The landing flow — thin actuator
# ---------------------------------------------------------------------------

proc runLandingFlow*(req: LandingRequest; token, repo: string;
                     cert: JsonNode;
                     dryRun: bool = false): Result[LandingResult, LandingFailure]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Executes the thin-actuator landing flow (ADR-0025 §1 M-B + Amendment A,
  ## plan Phase 0): certificate verification → A3 preflight (compare(B...H)
  ## == ahead; base freshness = platform ruleset strict) → SINGLE native-merge
  ## PUT (performMerge, merge_method=merge, sha=H — head pin) → post-merge
  ## continuity OBSERVATION (audit only, invariant 8 / A4) → journal.
  ## Identity is (B, H). No local merge-tree construction, no ref mutation,
  ## no self-CAS — self-owned merge authority = 0 (E1).
  if not isOid40(req.baseSha) or not isOid40(req.headSha):
    return err(landingFailure("INVALID_REQUEST", "B/H must be 40-hex OIDs (fail-closed)"))
  if req.prNumber <= 0:
    return err(landingFailure("MERGE_REQUIRES_PR",
      "native merge actuation requires a PR number (PUT /pulls/{n}/merge) — cert-only landings are no longer addressable (fail-closed)"))

  # Step 1 — certificate verification (Ed25519 + exact (B,H) binding +
  # current policy/scope digest equality; reuse of existing pure machinery).
  let bindingErr = verifyCertBinding(cert, req.baseSha, req.headSha)
  if bindingErr.len > 0:
    return err(landingFailure("CERT_INVALID", bindingErr))
  let envErr = verifyCertEnvDigests(cert)
  if envErr.len > 0:
    return err(landingFailure("ENV_DIGEST_MISMATCH", envErr))

  # Step 2 — A3 preflight (compare relation only; base freshness itself is
  # GitHub's ruleset strict at merge time — the tip==B observation was
  # removed as a duplicate of that platform guarantee):
  # compare(B...H).status must be "ahead" (H ⊇ B — the native merge commit
  # then carries tree(M) == tree(H) == certTree, invariant 7).
  # behind/identical/diverged/unrecognized abort — the certified tree
  # equality cannot hold (no /merges resolution path exists anymore).
  let compareRes = compareStatus(req.baseSha, req.headSha, token, repo)
  if compareRes.isErr:
    return err(compareRes.error)
  let relation = compareRes.get
  if relation.status == "ahead":
    discard # H ⊇ B — the only admissible relation (tree(M) == tree(H) == certTree)
  elif relation.status == "behind":
    return err(landingFailure("STALE_HEAD_BEHIND",
      "compare(B...H) = 'behind' — nothing to merge (abort, fail-closed)"))
  elif relation.status == "identical":
    return err(landingFailure("IDENTICAL_REF",
      "compare(B...H) = 'identical' — nothing to merge (abort, fail-closed)"))
  elif relation.status == "diverged":
    return err(landingFailure("DIVERGED_HEAD",
      "compare(B...H) = 'diverged' — tree(M) == certTree (invariant 7) cannot hold without " &
      "local merge-tree construction; re-admit from the current main tip (abort, fail-closed)"))
  else:
    return err(landingFailure("COMPARE_FAILED",
      "compare(B...H) status '" & relation.status & "' unrecognized (fail-closed)"))

  if dryRun:
    logInfo("landing_cli", "[dry-run] would merge PR " & $req.prNumber &
      " via native merge PUT (B " & req.baseSha[0 ..< 12] & ", H " & req.headSha[0 ..< 12] & ")")
    return ok(LandingResult(mergeSha: "", tempRefUsed: ""))

  # Step 3 — GitHub delegation (P12): the required-check binding (A2
  # pre-flight: context + canonical integration_id + strict) is the platform
  # ruleset's own configuration, enforced by GitHub at merge evaluation —
  # never re-derived here.

  # Step 4 — the SINGLE actuation: PUT /pulls/{n}/merge (performMerge,
  # merge_method=merge, sha=H — HEAD PIN only, no base CAS).
  let mergeRes = performMerge(req.prNumber, req.headSha, token, repo)
  if mergeRes.isErr:
    return err(landingFailure("MERGE_REJECTED",
      "merge PUT rejected (HTTP " & $mergeRes.error.httpStatus & "): " &
      mergeRes.error.ghMessage & " — main untouched (fail-closed)"))
  let m = mergeRes.get.mergeSha
  if not isOid40(m):
    return err(landingFailure("MERGE_UNRESOLVABLE",
      "merge PUT returned no merge commit OID (fail-closed)"))

  # Step 5 — post-merge continuity OBSERVATION (A4 / invariant 8): M was
  # created by GitHub; the shape + verifyContinuity checks are a fail-visible
  # audit backstop, NEVER landing authority (the landing already happened).
  # Observation failure journals the landed record and reports non-zero.
  var observedOk = true
  var observationNote = ""
  let shapeRes = resolveMergeShapeApi(m, token, repo)
  if shapeRes.isErr:
    observedOk = false
    observationNote = shapeRes.error
  else:
    let continuity = verifyContinuity(shapeRes.get, cert)
    if continuity != ccPassed:
      observedOk = false
      observationNote = "verifyContinuity(" & m[0 ..< 12] & ") = " & $continuity
  let outcome = if observedOk: "LANDED" else: "LANDED_OBSERVATION_MISMATCH"
  let landed = LandingResult(mergeSha: m, tempRefUsed: "")
  if not recordLanding(req, landed, "", outcome,
      if observedOk: "LANDING_OK" else: "CONTINUITY_MISMATCH",
      if observedOk: "native merge complete — M " & m[0 ..< 12]
                   else: "landed (M " & m[0 ..< 12] & ") but post-merge continuity observation failed: " & observationNote,
      token, repo):
    return err(landingFailure("JOURNAL_ERROR",
      "landing succeeded but journal write failed — NOT reported as done (fail-closed)"))
  if not observedOk:
    return err(landingFailure("CONTINUITY_MISMATCH",
      "post-merge continuity observation failed: " & observationNote &
      " (fail-visible backstop — the merge already landed; audit record written)"))
  ok(landed)

# ---------------------------------------------------------------------------
# CLI entry — `ax landing`
# ---------------------------------------------------------------------------

proc runLandingCli*(args: seq[string]): int
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let token = getEnv("GITHUB_TOKEN")
  if token.len == 0:
    stderr.writeLine("LANDING_FAIL {\"reasonCode\":\"NO_TOKEN\",\"reason\":\"GITHUB_TOKEN not set (ruleset-applying actuator identity; not the Landing App installation token) — fail-closed\"}")
    return 1

  var
    certPath = ""
    prNumber = 0
    mainSha = ""
    repo = DefaultRepo
    dryRun = false
  var i = 0
  while i < args.len:
    case args[i]
    of "--cert":
      if i + 1 >= args.len:
        logInfo("landing_cli", "usage: ax landing --cert <path> --pr <N> [--main-sha <sha>] [--repo owner/name] [--dry-run]")
        return 1
      certPath = args[i + 1]; inc i; inc i
    of "--pr":
      if i + 1 >= args.len:
        logInfo("landing_cli", "usage: ax landing --cert <path> --pr <N> [--main-sha <sha>] [--repo owner/name] [--dry-run]")
        return 1
      let parsed = safeParseInt(args[i + 1])
      if parsed.isErr:
        logInfo("landing_cli", "--pr requires an integer PR number")
        return 1
      prNumber = parsed.get(); inc i; inc i
    of "--main-sha":
      if i + 1 >= args.len:
        logInfo("landing_cli", "--main-sha requires a value")
        return 1
      mainSha = args[i + 1]; inc i; inc i
    of "--repo":
      if i + 1 >= args.len:
        logInfo("landing_cli", "--repo requires owner/name")
        return 1
      repo = args[i + 1]; inc i; inc i
    of "--dry-run":
      dryRun = true; inc i
    else:
      logInfo("landing_cli", "unknown argument: " & args[i] &
        " (usage: ax landing --cert <path> --pr <N> [--main-sha <sha>] [--repo owner/name] [--dry-run])")
      return 1

  # B: REQUIRED explicit input — no fallback to PR base (the main expectation
  # must be stated; an unset value denies, mirroring AXIOM_MAIN_SHA in
  # merge_cli).
  if mainSha.len == 0:
    mainSha = getEnv("AXIOM_MAIN_SHA")
  if not isOid40(mainSha):
    stderr.writeLine("LANDING_FAIL {\"reasonCode\":\"NO_MAIN_SHA\",\"reason\":\"expected main SHA (B) is required via --main-sha or AXIOM_MAIN_SHA (fail-closed)\"}")
    return 1
  if certPath.len == 0 and prNumber == 0:
    logInfo("landing_cli", "need --cert <path> or --pr <N> (certificate source)")
    return 1

  # Resolve H and the certificate (step-1 inputs).
  var headSha = ""
  if prNumber > 0:
    let headRes = fetchPrHead(prNumber, token, repo)
    if headRes.isErr:
      let f = headRes.error
      stderr.writeLine("LANDING_FAIL " & $ %*{"reasonCode": f.reasonCode, "reason": f.reason})
      return 1
    headSha = headRes.get
  var cert: JsonNode
  var certRef = ""
  if certPath.len > 0:
    if not fileExists(certPath):
      stderr.writeLine("LANDING_FAIL {\"reasonCode\":\"CERT_MISSING\",\"reason\":\"certificate artifact not found: " & certPath & " (fail-closed)\"}")
      return 1
    try:
      cert = parseJson(readFile(certPath))
    except CatchableError as e:
      stderr.writeLine("LANDING_FAIL {\"reasonCode\":\"CERT_UNREADABLE\",\"reason\":\"certificate artifact unreadable: " & e.msg & " (fail-closed)\"}")
      return 1
    certRef = certPath
    if headSha.len == 0:
      headSha = cert.getOrDefault("headSha").getStr("")
  else:
    let ledgerRes = loadLedgerCertFor(mainSha, headSha, token, repo)
    if ledgerRes.isErr:
      stderr.writeLine("LANDING_FAIL {\"reasonCode\":\"CERT_MISSING\",\"reason\":\"ledger certificate for (B " & mainSha[0 ..< 12] & ", H " & headSha[0 ..< 12] & ") not found: " & ledgerRes.error & " (fail-closed)\"}")
      return 1
    cert = ledgerRes.get
    certRef = "ledger:" & mainSha & ":" & headSha
  if not isOid40(headSha):
    stderr.writeLine("LANDING_FAIL {\"reasonCode\":\"NO_HEAD_SHA\",\"reason\":\"head SHA (H) unresolvable from PR/certificate (fail-closed)\"}")
    return 1

  let req = LandingRequest(baseSha: mainSha, headSha: headSha, certRef: certRef,
    prNumber: prNumber, prHeadRef: "")
  stdout.writeLine("LANDING_REQUEST " & landingRequestJson(req))
  logInfo("landing_cli", "landing request: " & landingRequestJson(req))

  let flowRes = runLandingFlow(req, token, repo, cert, dryRun)
  if flowRes.isErr:
    let f = flowRes.error
    stderr.writeLine("LANDING_FAIL " & $ %*{"reasonCode": f.reasonCode, "reason": f.reason})
    return 1
  let res = flowRes.get
  if dryRun:
    stdout.writeLine("LANDING_DRY_RUN {\"tempRefUsed\":\"" & res.tempRefUsed & "\"}")
    return 0
  stdout.writeLine("LANDING_OK " & $ %*{"mergeSha": res.mergeSha, "tempRefUsed": res.tempRefUsed})
  logInfo("landing_cli", "landing complete — main <- M " & res.mergeSha[0 ..< 12] & " (B " & req.baseSha[0 ..< 12] & ", H " & req.headSha[0 ..< 12] & ")")
  return 0

when isMainModule:
  quit(runLandingCli(commandLineParams()))
{.pop.}