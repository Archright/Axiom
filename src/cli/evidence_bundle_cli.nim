import core/trusted/layer_declaration
axiomLayer "presentation"
{.push raises: [CatchableError].}
# axiomIoBoundary

## `evidence-verify <export|verify>` — Evidence Bundle v2 CLI.
##
## Export is run-scoped: the selection comes from the proof state, never from
## a vault walk. Verify reads ONLY the bundle directory plus optional external
## observations; it never touches the subject checkout, the journal, or the
## vault. Exit codes for verify: 0 PASS, 1 FAIL, 2 usage/IO, 3 KERNEL_SKIPPED.

import std/json
import std/os
import std/strutils
import core/axiom_pragmas
import core/results
import infrastructure/logging_facade
import verification/canonical_json
import verification/evidence_bundle/bundle_export
import verification/evidence_bundle/bundle_verify

const UsageText = """Usage:
  evidence-verify export <proof-state.json> <owner/repo> <commit> <base-sha> <subject-root> <out-dir> [options]
      --vault <dir>            certificate vault (default: runtime canonical)
      --propositions <path>    propositionHash -> canonical proposition map (required)
      --run-id <id>            default: GITHUB_RUN_ID
      --run-attempt <n>        default: GITHUB_RUN_ATTEMPT
      --workflow-path <path>   default: GITHUB_WORKFLOW (or derived from GITHUB_WORKFLOW_REF)
      --workflow-ref <ref>     default: GITHUB_WORKFLOW_REF
      --event <name>           default: GITHUB_EVENT_NAME
      --head-sha <sha>         default: GITHUB_SHA
      --allow-reused           accept satisfactionSource=REUSED (default: FRESH only)

  evidence-verify verify <bundle-dir> [options]
      --expect-commit <sha>    require manifest.subject.commit == sha
      --attestation <path>     normalized GitHub attestation record
      --check-runs <path>      raw GitHub check-runs API response
      --ruleset <path>         raw GitHub ruleset API response
      --kernel                 re-execute leanSource + smtlib2 on the pinned toolchain
      --json                   emit one canonical JSON verdict object"""

func hasHelpFlag(args: seq[string]): bool {.raises: [].} =
  for arg in args:
    if arg == "--help" or arg == "-h":
      return true
  false

func workflowPathFromRef(workflowRef: string): string {.raises: [].} =
  ## "owner/repo/.github/workflows/x.yml@refs/heads/main" -> ".github/workflows/x.yml"
  let at = workflowRef.rfind('@')
  let head = if at >= 0: workflowRef[0 ..< at] else: workflowRef
  let parts = head.split('/')
  if parts.len < 3: return ""
  parts[2 .. ^1].join("/")

proc requireValue(args: seq[string]; i: var int; flag: string): string {.raises: [ValueError].} =
  if i + 1 >= args.len:
    raise newException(ValueError, flag & " requires a value")
  inc i
  args[i]

# ─── export ────────────────────────────────────────────────────────────────

proc runBundleExportCli(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if hasHelpFlag(args):
    echo UsageText
    return 0
  var opts = BundleExportOptions(
    runId: getEnv("GITHUB_RUN_ID", ""),
    runAttempt: getEnv("GITHUB_RUN_ATTEMPT", ""),
    workflowPath: getEnv("GITHUB_WORKFLOW", ""),
    workflowRef: getEnv("GITHUB_WORKFLOW_REF", ""),
    event: getEnv("GITHUB_EVENT_NAME", ""),
    headSha: getEnv("GITHUB_SHA", ""))
  if opts.workflowPath.len == 0:
    opts.workflowPath = workflowPathFromRef(opts.workflowRef)
  var positional: seq[string] = @[]
  var i = 0
  while i < args.len:
    case args[i]
    of "--vault":
      opts.vaultDir = requireValue(args, i, "--vault")
    of "--propositions":
      opts.propositionsPath = requireValue(args, i, "--propositions")
    of "--run-id":
      opts.runId = requireValue(args, i, "--run-id")
    of "--run-attempt":
      opts.runAttempt = requireValue(args, i, "--run-attempt")
    of "--workflow-path":
      opts.workflowPath = requireValue(args, i, "--workflow-path")
    of "--workflow-ref":
      opts.workflowRef = requireValue(args, i, "--workflow-ref")
    of "--event":
      opts.event = requireValue(args, i, "--event")
    of "--head-sha":
      opts.headSha = requireValue(args, i, "--head-sha")
    of "--allow-reused":
      opts.allowReused = true
    else:
      if args[i].startsWith("-"):
        logError("evidence_bundle_cli", "export: unknown flag: " & args[i])
        echo UsageText
        return 2
      positional.add(args[i])
    inc i
  if positional.len != 6:
    logError("evidence_bundle_cli", "export: expected 6 positional arguments, got " & $positional.len)
    echo UsageText
    return 2
  opts.proofStatePath = positional[0]
  opts.subjectRepo = positional[1]
  opts.subjectCommit = positional[2]
  opts.baseSha = positional[3]
  opts.subjectRoot = positional[4]
  opts.outDir = positional[5]

  let outcome = exportEvidenceBundle(opts)
  if outcome.isErr:
    logError("evidence_bundle_cli", "export: " & outcome.error)
    return 1
  let report = outcome.get
  echo "[bundle-export] OK " & report.outDir
  echo "[bundle-export] certs=" & $report.certCount & " sources=" & $report.sourceCount
  echo "[bundle-export] evidenceDigest=" & report.evidenceDigest
  echo "[bundle-export] provenanceDigest=" & report.provenanceDigest
  echo "[bundle-export] bundleDigest=" & report.bundleDigest
  0

# ─── verify ────────────────────────────────────────────────────────────────

proc runBundleVerifyCli(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if hasHelpFlag(args):
    echo UsageText
    return 0
  var opts = BundleVerifyOptions()
  var jsonOut = false
  var positional: seq[string] = @[]
  var i = 0
  while i < args.len:
    case args[i]
    of "--expect-commit":
      opts.expectCommit = requireValue(args, i, "--expect-commit")
    of "--attestation":
      opts.attestationPath = requireValue(args, i, "--attestation")
    of "--check-runs":
      opts.checkRunsPath = requireValue(args, i, "--check-runs")
    of "--ruleset":
      opts.rulesetPath = requireValue(args, i, "--ruleset")
    of "--kernel":
      opts.runKernel = true
    of "--json":
      jsonOut = true
    else:
      if args[i].startsWith("-"):
        logError("evidence_bundle_cli", "verify: unknown flag: " & args[i])
        echo UsageText
        return 2
      positional.add(args[i])
    inc i
  if positional.len != 1:
    logError("evidence_bundle_cli", "verify: expected one bundle directory, got " & $positional.len)
    echo UsageText
    return 2
  opts.bundleDir = positional[0]
  if not dirExists(opts.bundleDir):
    logError("evidence_bundle_cli", "verify: bundle directory does not exist: " & opts.bundleDir)
    return 2

  let outcome = verifyEvidenceBundle(opts)
  if jsonOut:
    echo canonicalJsonString(verifyOutcomeJson(outcome))
  else:
    for leg in outcome.legs:
      echo "[bundle-verify] " & leg.name & " " & legStatusText(leg.status) & " — " & leg.detail
    echo "[bundle-verify] exit=" & $outcome.exitCode & " certs=" & $outcome.certCount
  outcome.exitCode

# ─── dispatch ──────────────────────────────────────────────────────────────

proc runEvidenceBundleCli*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## `evidence-verify <export|verify> [args...]`.
  if args.len == 0 or args[0] == "--help" or args[0] == "-h":
    echo UsageText
    return 0
  case args[0]
  of "export":
    runBundleExportCli(args[1 .. ^1])
  of "verify":
    runBundleVerifyCli(args[1 .. ^1])
  else:
    logError("evidence_bundle_cli", "unknown bundle subcommand: " & args[0])
    echo UsageText
    2

{.pop.}