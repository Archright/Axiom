import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## Evidence CAS CLI — `ax evidence [ledger-append|ledger-lookup]`.
##
## The CI-facing surface for the durable evidence side-ref ledger
## (`refs/heads/axiom/evidence-cas`), mirroring the admission/cert ledger CLI
## conventions:
##   ledger-append  — append one evidence record JSON file (idempotent per
##                    evidenceKey: an already-present key is a no-op success
##                    returning the existing entry; never duplicated)
##   ledger-lookup  — read + re-hash-verify one record's payload bytes to
##                    stdout (HIT → payload; missing/mismatch/corrupt →
##                    fail-closed non-zero exit)
##
## Real network only via liveLedgerTransport (GITHUB_TOKEN); every failure
## path exits non-zero (fail-closed), mirroring admission_cli conventions.

import std/[json, os, strutils]
import infrastructure/logging_facade
import core/axiom_pragmas
import core/results
import verification/evidence_ledger
import verification/ledger_side_ref

const DefaultEvidenceRepo* = DefaultEvidenceCasRepo
  ## Side-ref target repo: AXIOM_REPO env overrides; GitHub token = GITHUB_TOKEN.
  ## The default value lives in evidence_ledger.DefaultEvidenceCasRepo — the
  ## single definition (no duplicated repo state).

proc evidenceRepo(): string {.raises: [].} =
  resolveEvidenceCasRepo()

proc evidenceToken(): string {.raises: [].} =
  getEnv("GITHUB_TOKEN", "")

func hasHelpFlag(args: seq[string]): bool {.raises: [].} =
  for arg in args:
    if arg == "--help" or arg == "-h":
      return true
  false

# ---------------------------------------------------------------------------
# ledger-append
# ---------------------------------------------------------------------------

type AppendArgs = object
  recordPath: string
  refName: string

func parseAppendArgs(args: seq[string]): Result[AppendArgs, string] {.raises: [].} =
  ## usage: ax evidence ledger-append <record.json> [--ref <refName>]
  ## Default ref = EvidenceCasRefName; --ref is validated to be a full ref
  ## path (fail-closed — a root-relative name would silently write the wrong
  ## ref).
  var parsed = AppendArgs(recordPath: "", refName: EvidenceCasRefName)
  var i = 0
  while i < args.len:
    case args[i]
    of "--ref":
      if i + 1 >= args.len: return err("--ref requires a ref name")
      parsed.refName = args[i + 1]; inc i
    else:
      if parsed.recordPath.len > 0:
        return err("unexpected argument: " & args[i])
      if args[i].startsWith("-"):
        return err("unknown flag: " & args[i])
      parsed.recordPath = args[i]
    inc i
  if parsed.recordPath.len == 0:
    return err("evidence record JSON path is required")
  if not parsed.refName.startsWith("refs/"):
    return err("--ref must be a full ref path (refs/...) — fail-closed")
  ok(parsed)

proc runLedgerAppendCli(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax evidence ledger-append <record.json> [--ref <refName>]
  ## Append one evidence record to the durable side-ref ledger. The record
  ## file is fully validated BEFORE any transport (schemaVersion, 64-hex
  ## key, sha256(payload) == payloadSha256) — a corrupt record never touches
  ## the network. Exactly-once per evidenceKey: an already-present key is an
  ## idempotent no-op success (exit 0), never a duplicate.
  let parsedRes = parseAppendArgs(args)
  if parsedRes.isErr:
    if hasHelpFlag(args):
      echo "Usage: ax evidence ledger-append <record.json> [--ref <refName>]"
      return 0
    logInfo("evidence_cli", "ledger-append: " & parsedRes.error)
    return 1
  let parsed = parsedRes.get
  let token = evidenceToken()
  if token.len == 0:
    logError("evidence_cli", "ledger-append: GITHUB_TOKEN not set (fail-closed)")
    return 1
  # Read + validate the record once — integrity before any transport.
  var text = ""
  try:
    text = readFile(parsed.recordPath)
  except CatchableError as e:
    logError("evidence_cli", "ledger-append: record unreadable: " & e.msg)
    return 1
  var recordOutcome: Result[EvidenceCasRecord, string]
  try:
    recordOutcome = parseEvidenceRecord(text)
  except Exception as e:
    recordOutcome = Result[EvidenceCasRecord, string](ok: false, err: "record parse raised: " & e.msg)
  if recordOutcome.isErr:
    logError("evidence_cli", "ledger-append: " & recordOutcome.error)
    return 1
  let record = recordOutcome.get
  let transport = liveLedgerTransport(token, parsed.refName)
  var appendOutcome: Result[EvidenceAppendOutcome, string]
  try:
    appendOutcome = appendEvidence(transport, evidenceRepo(), record, parsed.refName)
  except Exception as e:
    appendOutcome = Result[EvidenceAppendOutcome, string](ok: false, err: "append transport raised: " & e.msg)
  if appendOutcome.isErr:
    logError("evidence_cli", "ledger-append: " & appendOutcome.error)
    return 1
  if appendOutcome.get.alreadyPresent:
    echo "[evidence] ledger-append: no-op — key " & record.evidenceKey[0 ..< 12] &
      " already recorded (idempotent, existing entry returned)"
  else:
    echo "[evidence] ledger-append: OK — key " & record.evidenceKey[0 ..< 12] &
      " tip " & appendOutcome.get.tipSha
  return 0

# ---------------------------------------------------------------------------
# ledger-lookup
# ---------------------------------------------------------------------------

type LookupArgs = object
  evidenceKey: string
  refName: string

func parseLookupArgs(args: seq[string]): Result[LookupArgs, string] {.raises: [].} =
  ## usage: ax evidence ledger-lookup <64-hex-evidenceKey> [--ref <refName>]
  var parsed = LookupArgs(evidenceKey: "", refName: EvidenceCasRefName)
  var i = 0
  while i < args.len:
    case args[i]
    of "--ref":
      if i + 1 >= args.len: return err("--ref requires a ref name")
      parsed.refName = args[i + 1]; inc i
    else:
      if parsed.evidenceKey.len > 0:
        return err("unexpected argument: " & args[i])
      if args[i].startsWith("-"):
        return err("unknown flag: " & args[i])
      parsed.evidenceKey = args[i].toLowerAscii()
    inc i
  if parsed.evidenceKey.len == 0:
    return err("evidence key is required")
  if not isValidEvidenceKey(parsed.evidenceKey):
    return err("evidence key must be 64 lowercase hex chars — fail-closed")
  if not parsed.refName.startsWith("refs/"):
    return err("--ref must be a full ref path (refs/...) — fail-closed")
  ok(parsed)

proc runLedgerLookupCli(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## usage: ax evidence ledger-lookup <64-hex-evidenceKey> [--ref <refName>]
  ## Read the record and emit the VERIFIED payload bytes on stdout (payload +
  ## trailing newline). The payload bytes are re-hashed and the identity chain
  ## re-verified on every read; missing / mismatched / corrupt → non-zero
  ## exit with nothing on stdout (fail-closed, no partial trust).
  let parsedRes = parseLookupArgs(args)
  if parsedRes.isErr:
    if hasHelpFlag(args):
      echo "Usage: ax evidence ledger-lookup <64-hex-evidenceKey> [--ref <refName>]"
      return 0
    logInfo("evidence_cli", "ledger-lookup: " & parsedRes.error)
    return 1
  let parsed = parsedRes.get
  let token = evidenceToken()
  if token.len == 0:
    logError("evidence_cli", "ledger-lookup: GITHUB_TOKEN not set — ledger read refused (fail-closed)")
    return 1
  var lookupOutcome: Result[string, string]
  try:
    lookupOutcome = lookupEvidence(liveLedgerTransport(token, parsed.refName), evidenceRepo(),
      parsed.evidenceKey, parsed.refName)
  except Exception as e:
    lookupOutcome = Result[string, string](ok: false, err: "lookup transport raised: " & e.msg)
  if lookupOutcome.isErr:
    logError("evidence_cli", "ledger-lookup: " & lookupOutcome.error)
    return 1
  echo lookupOutcome.get
  return 0

# ---------------------------------------------------------------------------
# dispatch
# ---------------------------------------------------------------------------

proc runEvidenceCli*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## `ax evidence <subcommand> [args...]` — subcommand dispatch (admission_cli
  ## pattern). Unknown subcommand → usage + exit 1.
  if args.len == 0 or args[0] == "--help" or args[0] == "-h":
    echo "Usage: ax evidence [ledger-append|ledger-lookup] [args...]"
    return 0
  case args[0]
  of "ledger-append":
    runLedgerAppendCli(args[1 .. ^1])
  of "ledger-lookup":
    runLedgerLookupCli(args[1 .. ^1])
  else:
    echo "Usage: ax evidence [ledger-append|ledger-lookup] [args...]"
    1
