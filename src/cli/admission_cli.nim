import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Admission CLI — `ax admission [mint|append|show|list]` (ADR-0022).
##
## The trusted-writer surface for the Admission Artifact A:
##   mint    — merge facts → A payload JSON (canonical, stdout)
##   append  — CAS-append the artifact to the admissions side ref (idempotent
##             by payload digest: same digest already at the tip tree = no-op)
##   show    — read one artifact from the admissions ref (read-only)
##   list    — list artifact entries under the admissions ref (read-only)
##
## The `accept` subcommand (R(H) append to refs/heads/axiom/canonical-acceptances)
## was RETIRED 2026-10-07 (authority_contract.md §5.4 — GitHub required check +
## merge queue is the authoritative acceptance; the duplicate acceptance ledger
## surface was retired, ref itself preserved). `ax admission accept` now falls
## through to the unknown-subcommand path (usage + exit 1, fail-closed).
##
## Real network only via liveLedgerTransport (GITHUB_TOKEN); every failure
## path exits non-zero (fail-closed), mirroring cert_cli conventions.

import std/[json, os, strutils, times]
import infrastructure/logging_facade
import core/axiom_pragmas
import core/parsers/safe_parsers
import core/results
import verification/admission_artifact
import verification/ledger_side_ref
import verification/canonical_json

const DefaultAdmissionRepo* = "Archright/Axiom"
  ## Side-ref target repo: AXIOM_REPO env overrides; GitHub token = GITHUB_TOKEN.

proc admissionRepo(): string {.raises: [].} =
  let r = getEnv("AXIOM_REPO", "")
  if r.len > 0: r else: DefaultAdmissionRepo

proc admissionToken(): string {.raises: [].} =
  getEnv("GITHUB_TOKEN", "")

proc currentUtcTimestamp(): string {.raises: [].} =
  ## RFC 3339 UTC timestamp (writer clock for evaluatedAt).
  getTime().utc.format("yyyy-MM-dd'T'HH:mm:ss'Z'")

func parseIntSafe(s: string): int {.raises: [].} =
  ## Exception-free integer parse (0 on failure — caller validates range).
  safeParseInt(s.strip()).getOrDefault(0)

func hasHelpFlag(args: seq[string]): bool {.raises: [].} =
  for arg in args:
    if arg == "--help" or arg == "-h":
      return true
  false

# ---------------------------------------------------------------------------
# mint
# ---------------------------------------------------------------------------

type MintArgs = object
  prNumber: int
  headSha: string
  mainSha: string
  mergeOid: string
  landingParent1: string
  runId: string
  runAttempt: string
  jwt: string
  jsonMode: bool
  reasonCode: string
  verdict: string

func parseMintArgs(args: seq[string]): Result[MintArgs, string] {.raises: [].} =
  ## Strict flag parser: every fact must be supplied at the I/O boundary —
  ## mint never guesses merge facts (fail-closed). --verdict/--reason-code
  ## default to mergeGo/"" (the PASS path); any other verdict is a refusal
  ## artifact and must be explicitly requested. --landing-parent1 is the
  ## caller-observed first parent of the merge commit C' (required for the
  ## merge-commit shape; empty for an FF shape — mintAdmissionPayload enforces
  ## the shape contract, see admission_artifact.nim mintAdmissionPayload).
  var parsed = MintArgs(prNumber: 0, jsonMode: false, reasonCode: "", verdict: "mergeGo")
  var i = 0
  var sawMergeOid = false
  while i < args.len:
    case args[i]
    of "--pr":
      if i + 1 >= args.len: return err("--pr requires a number")
      parsed.prNumber = parseIntSafe(args[i + 1]); inc i
    of "--head":
      if i + 1 >= args.len: return err("--head requires a 40-hex OID")
      parsed.headSha = args[i + 1].toLowerAscii(); inc i
    of "--main":
      if i + 1 >= args.len: return err("--main requires a 40-hex OID")
      parsed.mainSha = args[i + 1].toLowerAscii(); inc i
    of "--merge-oid":
      if i + 1 >= args.len: return err("--merge-oid requires a 40-hex OID")
      parsed.mergeOid = args[i + 1].toLowerAscii(); sawMergeOid = true; inc i
    of "--landing-parent1":
      if i + 1 >= args.len: return err("--landing-parent1 requires a 40-hex OID or empty")
      parsed.landingParent1 = args[i + 1].toLowerAscii(); inc i
    of "--run-id":
      if i + 1 >= args.len: return err("--run-id requires a value")
      parsed.runId = args[i + 1]; inc i
    of "--run-attempt":
      if i + 1 >= args.len: return err("--run-attempt requires a value")
      parsed.runAttempt = args[i + 1]; inc i
    of "--jwt":
      if i + 1 >= args.len: return err("--jwt requires the OIDC token")
      parsed.jwt = args[i + 1]; inc i
    of "--json":
      parsed.jsonMode = true
    of "--verdict":
      if i + 1 >= args.len: return err("--verdict requires a value")
      parsed.verdict = args[i + 1]; inc i
    of "--reason-code":
      if i + 1 >= args.len: return err("--reason-code requires a value")
      parsed.reasonCode = args[i + 1]; inc i
    else:
      return err("unknown argument: " & args[i])
    inc i
  if parsed.prNumber <= 0: return err("--pr N is required (positive)")
  if not isOid40(parsed.headSha): return err("--head must be 40-hex lowercase")
  if not isOid40(parsed.mainSha): return err("--main must be 40-hex lowercase")
  if not sawMergeOid: return err("--merge-oid is required (the caller-observed C')")
  if not isOid40(parsed.mergeOid): return err("--merge-oid must be 40-hex lowercase")
  if parsed.runId.len == 0 or parsed.runAttempt.len == 0:
    return err("--run-id and --run-attempt are required")
  if parsed.jwt.len == 0: return err("--jwt is required (execution identity)")
  ok(parsed)

proc runMintCli(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax admission mint --pr N --head <H> --main <M> --merge-oid <C'>
  ##        [--landing-parent1 <C'^1>] --run-id <R> --run-attempt <A>
  ##        --jwt <token> [--json]
  ## Merge facts → canonical A payload JSON on stdout. The JWT is DECODED
  ## (claims only) into executionIdentity; the raw token is NOT embedded.
  let parsedRes = parseMintArgs(args)
  if parsedRes.isErr:
    if hasHelpFlag(args):
      echo "Usage: ax admission mint --pr N --head <H> --main <M> --merge-oid <C'> [--landing-parent1 <C'^1>] --run-id <R> --run-attempt <A> --jwt <token> [--json]"
      return 0
    logInfo("admission_cli", "mint: " & parsedRes.error)
    return 1
  let parsed = parsedRes.get
  var claimsOutcome: Result[ExecutionIdentityClaims, string]
  try:
    claimsOutcome = decodeExecutionIdentityClaims(parsed.jwt)
  except Exception as e:
    claimsOutcome = Result[ExecutionIdentityClaims, string](ok: false, err: "jwt decode raised: " & e.msg)
  if claimsOutcome.isErr:
    logError("admission_cli", "mint: " & claimsOutcome.error)
    return 1
  let facts = AdmissionMergeFacts(
    verdict: parsed.verdict,
    reasonCode: parsed.reasonCode,
    prNumber: parsed.prNumber,
    headSha: parsed.headSha,
    landingCandidateSha: parsed.mergeOid,
    landingParent1: parsed.landingParent1,
    evaluatedMainSha: parsed.mainSha,
    ledgerCertId: "",
    evaluatedAt: currentUtcTimestamp(),
    runId: parsed.runId,
    runAttempt: parsed.runAttempt)
  let payloadRes = mintAdmissionPayload(facts)
  if payloadRes.isErr:
    logError("admission_cli", "mint: " & payloadRes.error)
    return 1
  let identity = buildExecutionIdentity(claimsOutcome.get)
  let envelope = %*{"payload": payloadRes.get, "executionIdentity": identity}
  let canonical = canonicalJsonString(envelope)
  echo canonical
  return 0

# ---------------------------------------------------------------------------
# append
# ---------------------------------------------------------------------------

type AppendArgs = object
  artifactPath: string
  refName: string

func parseAppendArgs(args: seq[string]): Result[AppendArgs, string] {.raises: [].} =
  ## usage: ax admission append <artifact.json> [--ref <refName>]
  ## Default ref = AdmissionsRefName; --ref is validated to be a full ref path
  ## (fail-closed — a root-relative name would silently write the wrong ref).
  var parsed = AppendArgs(artifactPath: "", refName: AdmissionsRefName)
  var i = 0
  while i < args.len:
    case args[i]
    of "--ref":
      if i + 1 >= args.len: return err("--ref requires a ref name")
      parsed.refName = args[i + 1]; inc i
    else:
      if parsed.artifactPath.len > 0:
        return err("unexpected argument: " & args[i])
      if args[i].startsWith("-"):
        return err("unknown flag: " & args[i])
      parsed.artifactPath = args[i]
    inc i
  if parsed.artifactPath.len == 0:
    return err("artifact JSON path is required")
  if not parsed.refName.startsWith("refs/"):
    return err("--ref must be a full ref path (refs/...) — fail-closed")
  ok(parsed)

proc runAppendCli(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax admission append <artifact.json> [--ref <refName>]
  ## CAS-append the artifact to the admissions side ref. Idempotent: when a
  ## blob with the same payload digest already exists anywhere under the tip
  ## tree, the append is a no-op success (the artifact is already recorded).
  let parsedRes = parseAppendArgs(args)
  if parsedRes.isErr:
    if hasHelpFlag(args):
      echo "Usage: ax admission append <artifact.json> [--ref <refName>]"
      return 0
    logInfo("admission_cli", "append: " & parsedRes.error)
    return 1
  let parsed = parsedRes.get
  let token = admissionToken()
  if token.len == 0:
    logError("admission_cli", "append: GITHUB_TOKEN not set (fail-closed)")
    return 1
  # Read the artifact once — digest + validity before any transport.
  var text = ""
  try:
    text = readFile(parsed.artifactPath)
  except CatchableError as e:
    logError("admission_cli", "append: artifact unreadable: " & e.msg)
    return 1
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError as e:
    logError("admission_cli", "append: artifact JSON malformed: " & e.msg)
    return 1
  let payloadRes = artifactPayloadFromEnvelope(node)
  if payloadRes.isErr:
    logError("admission_cli", "append: " & payloadRes.error)
    return 1
  let digestRes = admissionPayloadDigest(payloadRes.get)
  if digestRes.isErr:
    logError("admission_cli", "append: " & digestRes.error)
    return 1
  let transport = liveLedgerTransport(token, parsed.refName)
  var existsOutcome: Result[bool, string]
  try:
    existsOutcome = artifactExistsAtTip(transport, admissionRepo(), digestRes.get, parsed.refName)
  except Exception as e:
    existsOutcome = Result[bool, string](ok: false, err: "duplicate check raised: " & e.msg)
  if existsOutcome.isErr:
    logError("admission_cli", "append: " & existsOutcome.error)
    return 1
  if existsOutcome.get:
    echo "[admission] append: no-op — payload digest " & digestRes.get[0 ..< 12] & " already at ref tip"
    return 0
  var appendOutcome: Result[string, string]
  try:
    appendOutcome = appendAdmissionArtifact(transport, admissionRepo(), parsed.artifactPath, parsed.refName)
  except Exception as e:
    appendOutcome = Result[string, string](ok: false, err: "append transport raised: " & e.msg)
  if appendOutcome.isErr:
    logError("admission_cli", "append: " & appendOutcome.error)
    return 1
  echo "[admission] append: OK — tip " & appendOutcome.get & " (digest " & digestRes.get[0 ..< 12] & ")"
  return 0

# ---------------------------------------------------------------------------
# show / list — read-only
# ---------------------------------------------------------------------------

func parseShowArgs(args: seq[string]): Result[tuple[runId, runAttempt, refName: string], string] {.raises: [].} =
  ## usage: ax admission show --run-id <R> --run-attempt <A> [--ref <refName>]
  if args.len == 0:
    return err("--run-id/--run-attempt required")
  var runId = ""
  var runAttempt = ""
  var refName = AdmissionsRefName
  var i = 0
  while i < args.len:
    case args[i]
    of "--run-id":
      if i + 1 >= args.len: return err("--run-id requires a value")
      runId = args[i + 1]; inc i
    of "--run-attempt":
      if i + 1 >= args.len: return err("--run-attempt requires a value")
      runAttempt = args[i + 1]; inc i
    of "--ref":
      if i + 1 >= args.len: return err("--ref requires a ref name")
      refName = args[i + 1]; inc i
    else:
      return err("unknown argument: " & args[i])
    inc i
  if runId.len == 0 or runAttempt.len == 0:
    return err("--run-id and --run-attempt required")
  if not refName.startsWith("refs/"):
    return err("--ref must be a full ref path (refs/...) — fail-closed")
  ok((runId, runAttempt, refName))

proc runShowCli(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax admission show --run-id <R> --run-attempt <A> [--ref <refName>]
  ## Read the artifact (canonical JSON) to stdout. Read-only.
  let parsedRes = parseShowArgs(args)
  if parsedRes.isErr:
    if hasHelpFlag(args):
      echo "Usage: ax admission show --run-id <R> --run-attempt <A> [--ref <refName>]"
      return 0
    logInfo("admission_cli", "show: " & parsedRes.error)
    return 1
  let parsed = parsedRes.get
  let token = admissionToken()
  if token.len == 0:
    logError("admission_cli", "show: GITHUB_TOKEN not set (fail-closed)")
    return 1
  var readOutcome: Result[JsonNode, string]
  try:
    readOutcome = readAdmissionArtifact(liveLedgerTransport(token, parsed.refName), admissionRepo(),
      parsed.runId, parsed.runAttempt, parsed.refName)
  except Exception as e:
    readOutcome = Result[JsonNode, string](ok: false, err: "read raised: " & e.msg)
  if readOutcome.isErr:
    logError("admission_cli", "show: " & readOutcome.error)
    return 1
  echo canonicalJsonString(readOutcome.get)
  return 0

proc runListCli(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax admission list [--ref <refName>] — enumerate artifact entry
  ## names under the admissions ref tip tree. Read-only.
  var refName = AdmissionsRefName
  var i = 0
  while i < args.len:
    case args[i]
    of "--ref":
      if i + 1 >= args.len:
        logInfo("admission_cli", "list: --ref requires a ref name")
        return 1
      refName = args[i + 1]; inc i
    else:
      logInfo("admission_cli", "list: unknown argument: " & args[i])
      return 1
    inc i
  let token = admissionToken()
  if token.len == 0:
    logError("admission_cli", "list: GITHUB_TOKEN not set (fail-closed)")
    return 1
  var listOutcome: Result[seq[string], string]
  try:
    listOutcome = listRefEntryNames(liveLedgerTransport(token, refName), admissionRepo(), refName)
  except Exception as e:
    listOutcome = Result[seq[string], string](ok: false, err: "list raised: " & e.msg)
  if listOutcome.isErr:
    logError("admission_cli", "list: " & listOutcome.error)
    return 1
  for name in listOutcome.get:
    echo name
  echo "[admission] Entries: " & $listOutcome.get.len
  return 0

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

proc runAdmissionCli*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## `ax admission <subcommand> [args...]` — subcommand dispatch (cert_cli
  ## pattern). Unknown subcommand → usage + exit 1.
  if args.len == 0 or args[0] == "--help" or args[0] == "-h":
    echo "Usage: ax admission [mint|append|show|list] [args...]"
    return 0
  case args[0]
  of "mint":
    runMintCli(args[1 .. ^1])
  of "append":
    runAppendCli(args[1 .. ^1])
  of "show":
    runShowCli(args[1 .. ^1])
  of "list":
    runListCli(args[1 .. ^1])
  else:
    echo "Usage: ax admission [mint|append|show|list] [args...]"
    1
{.pop.}