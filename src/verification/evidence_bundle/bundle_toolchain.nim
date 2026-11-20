import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Toolchain measurement shared by bundle export and bundle verify.
##
## Both commands must measure the SAME live toolchain with the SAME rules:
## the exporter records it, the verifier compares it. Keeping one definition
## here prevents the two sides from drifting into different probes (a
## verifier that accepts a pin the exporter could never have produced is
## theater).

import std/json
import std/os
import std/osproc
import std/strutils
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/types/z3_solver_config
import infrastructure/process_utils
import verification/attestation_orchestrator
import verification/evidence_cas
import verification/kernel_reexecution

when fileExists("src/generated/build_env.nim"):
  import generated/build_env
else:
  const
    BuildEnvZ3Version = ""
    VerifierBuildId = ""

const
  ProbeTimeoutMs* = 30_000

func parseLeanVersion*(output: string): string {.raises: [].} =
  let marker = "version "
  let idx = output.find(marker)
  if idx < 0: return ""
  let rest = output[idx + marker.len .. ^1].strip()
  var version = ""
  for ch in rest:
    if ch in {'0'..'9', '.'}:
      version.add(ch)
    elif version.len > 0:
      break
  version.strip(chars = {'.'})

proc resolveLeanCommand*(): string {.raises: [].} =
  let envCmd = getEnv("AXIOM_LEAN_CMD", "")
  if envCmd.len > 0: return envCmd
  "lean"

proc probeLeanVersion*(): string {.raises: [].} =
  let (output, code) = execCmdWithTimeout(resolveLeanCommand() & " --version",
    timeoutMs = ProbeTimeoutMs)
  if code == 0: parseLeanVersion(output) else: ""

proc leanCheckerPath*(): string {.raises: [].} =
  let envCmd = getEnv("AXIOM_LEANCHECKER_CMD", "")
  if envCmd.len > 0 and fileExists(envCmd): return envCmd
  try:
    findExe("leanchecker")
  except OSError:
    ""

proc readAppSha256*(): Result[string, string] {.
  raises: [CatchableError], axiomDecision(id = "DECISION-0836",
    reason = "The verifier executable identity is unmeasurable rather than guessed (fail-closed)",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  let app = getAppFilename()
  if app.len == 0 or not fileExists(app):
    return err("cannot resolve the verifier executable for verifierBundleSha256")
  ok(sha256Hex(readFile(app)))

func measuredVerifierBuildId*(): string {.raises: [].} =
  when declared(VerifierBuildId):
    verifierEngineBuildId()
  else:
    "unmeasured"

proc buildToolchain*(repoRoot: string): Result[JsonNode, string] {.
  raises: [CatchableError], axiomDecision(id = "DECISION-0837",
    reason = "A bundle may not record a toolchain pin that was not measured live (fail-closed)",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  let buildId = measuredVerifierBuildId()
  if buildId.len != 64 or buildId == "unmeasured":
    return err("verifier build identity is unmeasured — rebuild with bin/hermetic_build (fail-closed)")
  let appSha = readAppSha256()
  if appSha.isErr: return err(appSha.error)
  let toolchainPath = repoRoot / LeanToolchainPinPath
  if not fileExists(toolchainPath):
    return err("Lean toolchain pin file is missing: " & LeanToolchainPinPath)
  let leanToolchainFile = readFile(toolchainPath).strip()
  if leanToolchainFile.len == 0:
    return err("Lean toolchain pin file is empty")
  let leanVersion = probeLeanVersion()
  if leanVersion.len == 0:
    return err("cannot measure the executed Lean version (lean --version failed)")
  var checkerSha = ""
  let checker = leanCheckerPath()
  if checker.len > 0:
    checkerSha = sha256Hex(readFile(checker))
  let z3Bin = resolveZ3Path()
  if z3Bin.len == 0 or not fileExists(z3Bin):
    return err("Z3 binary is not resolvable")
  if not z3BinaryChecksumAccepted(z3Bin, repoRoot):
    return err("Z3 binary does not match data/policy/z3_binary_checksums.json (fail-closed)")
  let z3Sha = sha256Hex(readFile(z3Bin))
  var node = newJObject()
  node["verifierBuildId"] = %buildId
  node["verifierBundleSha256"] = %appSha.get
  node["nimVersion"] = %($NimVersion)
  node["leanToolchainFile"] = %leanToolchainFile
  node["leanVersion"] = %leanVersion
  node["leancheckerSha256"] = %checkerSha
  node["z3Version"] = %BuildEnvZ3Version
  node["z3BinarySha256"] = %z3Sha
  ok(node)

proc buildPolicy*(repoRoot: string): Result[JsonNode, string] {.
  raises: [CatchableError], axiomDecision(id = "DECISION-0838",
    reason = "Policy/scope digests are required semantic inputs; a missing member is an err",
    adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "VS-2a").} =
  let policy =
    try:
      collectPolicyDigest(repoRoot)
    except CatchableError as exc:
      return err(exc.msg)
    except Exception as exc:
      return err("evidence_cas: policy digest collection aborted: " & exc.msg)
  if policy.isErr: return err(policy.error)
  let scope =
    try:
      collectScopeDigest(repoRoot)
    except CatchableError as exc:
      return err(exc.msg)
    except Exception as exc:
      return err("evidence_cas: scope digest collection aborted: " & exc.msg)
  if scope.isErr: return err(scope.error)
  var node = newJObject()
  node["policyDigest"] = %policy.get
  node["scopeDigest"] = %scope.get
  ok(node)

{.pop.}