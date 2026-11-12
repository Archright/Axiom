import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/os
import std/tables
import std/strutils
import core/axiom_pragmas

proc stateJoin(parts: varargs[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## AXIOM_STATE_DIR 설정 시 <state>/<parts...>, 미설정 시 기존 CWD 상대 경로 그대로(zero-diff).
  let base = block:
    let v = getEnv("AXIOM_STATE_DIR")
    if v.len > 0: v else: getCurrentDir()
  result = base
  for p in parts: result = joinPath(result, p)

type CertVaultRole* = enum
  cvCanonicalRead
  cvRuntimeCanonical
  cvTransientWrite

func resolveCertificate*(role: CertVaultRole): string {.axiomDecision(id = "DECISION-0621", reason = "Semantic role-based certificate vault resolution: cvCanonicalRead for reference/engineering readers (src/verification/certificates), cvRuntimeCanonical for current-product-truth runtime store (data/trusted/certificates), cvTransientWrite for build-time staging (build/certificates)", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), raises: [].} =
  case role
  of cvCanonicalRead:
    result = "src" / "verification" / "certificates"
  of cvRuntimeCanonical:
    result = "data" / "trusted" / "certificates"
  of cvTransientWrite:
    result = "build" / "certificates"

var promotionActive* {.threadvar.}: bool

proc resolveVaultDirForWrite*(
  taskVaultDir: string;
  env: Table[string, string]
): string {.axiomDecision(id = "DECISION-0622", reason = "Write-side vault resolver with canonical-path write guard; rejects src/verification/certificates unless promotionActive is set", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), raises: [CatchableError].} =
  let envVaultDir = env.getOrDefault("AXIOM_PROVE_VAULT_DIR", "")
  if taskVaultDir.len > 0:
    result = taskVaultDir
  elif envVaultDir.len > 0:
    result = envVaultDir
  else:
    result = stateJoin("build", "certificates")
  let canonicalDir = resolveCertificate(cvCanonicalRead)
  if result.startsWith(canonicalDir) and not promotionActive:
    raise newException(CatchableError, "DIRECT CANONICAL WRITE FORBIDDEN — must go through explicit promotion context (set promotionActive=true or use --promote flag)")

proc resolveVaultDir*(
  taskVaultDir: string;
  env: Table[string, string]
): string {.axiomDecision(id = "DECISION-0623", reason = "Backward-compat wrapper for resolveVaultDirForWrite; defaults to write mode (build/certificates)", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32").} =
  result = resolveVaultDirForWrite(taskVaultDir, env)