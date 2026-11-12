import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

## Closure Manifest Provider — compiler-truth dependency closure (VS-T).
##
## Authority handoff (docs/evidence/vst_dependency_authority_handoff_2026-11-08.md):
## the gate CAS closure basis is the Nim compiler's own dependency closure,
## captured as validated `nim genDepend` manifests (execution contract:
## docs/spec/nim_gendepend_quirks.md; generator:
## tools/ci/generate_gate_closure_manifests.sh reusing the production
## pp_capture_manifest bash contract). This module only READS and VALIDATES
## manifests — hashing stays in the consumer (gate_cas), which preserves its
## CAS hash schema (sorted Merkle over source ∪ closure, "\x02" pairwise
## domain separator, "" = Unresolved = fail-closed no-key).
##
## Proc surface (proc→func ratchet, AGENTS.md §0.6): exactly two
## I/O-boundary procs — genDependProfile (filesystem probe of resolution
## roots) and loadProjectClosure (manifest read + validation). The manifest
## parser is a func; single-use I/O helpers are inlined at their call sites.
##
## Fail-closed contract: a missing, malformed, identity-mismatched or
## structurally stale manifest yields @[] — never a partial closure. The
## caller turns @[] into "" → no CAS key → compile/execute path
## (verification_dag_contract.md §4/§5). A missing manifest is NEVER a
## cache HIT (§0.9 theater prohibition).
##
## ManifestIdentity binding (validated at every read): nim binary sha256 +
## full `nim --version` output, the canonical genDepend profile flag string
## (genDependProfile — single authority, mirrors the flag-equivalent subset
## of config.nims + config/paths.nims resolution roots used by the real
## per-gate compile), and the per-run mktemp CWD contract token. The live
## toolchain digest behind this binding is computed once per process and
## compared on every read (ToolchainIdentity below — DEBT#522). genDepend
## .deps lines are absolute paths including stdlib/nimble files — only
## project files (under the repository root) enter the returned closure;
## `when fileExists(...)` probe targets that currently exist join it (quirk
## 4: the throwaway capture CWD takes the absent branch, the real compile
## the present one, so probe existence+content must be bound into the
## hashed set).

import std/[os, osproc, strutils, algorithm]
import core/crypto/hash_kernel
import core/interfaces/logging_hub
import core/types/results
import core/utils/io_utils
import core/trusted/axiom_pragmas_lite
# axiomIoBoundary

const
  ManifestSchema* = "gate-closure-manifest/1"
    ## On-disk manifest schema token; a mismatch rejects the manifest.
  ManifestDirRel* = ".axiom" / "cache" / "gate_closure"
    ## Manifest store (machine-local cache, never committed).
  CwdContractToken* = "mktemp-d-per-run"
    ## Per-run isolated mktemp CWD+nimcache contract (quirks doc §execution
    ## contract); the load-bearing /tmp-CWD rule for genDepend capture.
  InjectedNimblePkgs = ["checksums", "ed25519", "fusion", "malebolgia", "nimcrypto"]
    ## config/paths.nims injectAxiomDependencies list — the same nimble
    ## resolution roots the real compile injects, in the same order.

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc genDependProfile*(repoRoot: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Canonical genDepend profile — the single authority for the flag string
  ## (the generator receives it as an argument; every read validates the
  ## manifest against a recomputation). Flag-equivalent to the REAL per-gate
  ## compile (`nim c --hints:off -d:release --skipUserCfg:on
  ## -d:ThreadPoolSize=14 <src>` with config.nims loaded, CWD=repoRoot):
  ## same resolution roots (config.nims + config/paths.nims switch set +
  ## nimRoot + injected nimble packages), same branch-relevant defines;
  ## config load is replaced by the explicit root list because the capture
  ## CWD is a throwaway directory (quirk 5) — equivalence proof in the
  ## evidence doc. Hardened over the hook profile with --skipUserCfg
  ## --skipCfg (user-cfg determinism hole) — with --skipCfg every search
  ## root is explicit and bound into this string.
  if repoRoot.len == 0:
    return ""
  var parts: seq[string] = @[
    "--hints:off",
    "--skipParentCfg", "--skipProjCfg", "--skipUserCfg", "--skipCfg",
    "--threads:on",  # config/effects.nims switch("threads") — malebolgia
                     # threadpool imports fail without it (Thread undeclared)
    "--mm:arc",      # config/effects.nims switch("mm", "arc") — branch
                     # defines gcArc/gcOrc must match the real compile
    "--path:" & repoRoot,
    "--path:" & (repoRoot / "src"),
    "--path:" & (repoRoot / "tests" / "gateway"),
    "--path:" & (repoRoot / "src" / "shared_types"),
    "--path:" & (repoRoot / "tools"),
  ]
  block nimRootResolution:
    # Choosenim layout: <toolchain>/bin/nim → the toolchain root carries
    # compiler/ (needed by gates importing compiler/*, e.g.
    # evidence_truth_boundary_gate; mirrors config.nims's nimRoot path
    # switch). Skipped when the layout does not hold compiler sources.
    let nimExe = try: findExe("nim") except CatchableError: ""
    if nimExe.len > 0:
      try:
        let root = nimExe.parentDir().parentDir()
        if dirExists(root / "compiler"):
          parts.add("--path:" & root)
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch)
  let pkgs2 = getEnv("HOME") / ".nimble" / "pkgs2"
  for pkg in InjectedNimblePkgs:
    # Deterministic pick of the injected nimble package dir: first match in
    # sorted order (config/paths.nims uses walkDir order; sorted is the
    # deterministic form of the same rule — a pick difference only affects
    # non-project resolution, which is filtered out of the closure).
    try:
      if dirExists(pkgs2):
        var candidates: seq[string] = @[]
        for kind, path in walkDir(pkgs2):
          if kind == pcDir and path.extractFilename().startsWith(pkg & "-"):
            candidates.add(path)
        if candidates.len > 0:
          candidates.sort(cmp)
          parts.add("--path:" & candidates[0])
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  parts.add("-d:release")
  parts.add("-d:ThreadPoolSize=14")
  parts.join(" ")

type
  ManifestParse = object
    schema, main, nimSha, nimVersion, flags, cwdContract: string
    closure: seq[string]
    probes: seq[string]

  # Process-lifetime toolchain identity digest (DEBT#522 remaining half,
  # 2026-11-10). loadProjectClosure validates NIM_SHA256/NIM_VERSION against
  # the LIVE toolchain on every read; the digest inputs are pure functions of
  # the nim binary's bytes, so the first successful computation in a process
  # is reused for later calls. Invariance assumption: the bytes behind a
  # resolved nim path do not change within a process lifetime — the same
  # assumption the accepted gate_memo threadvar caches (computeBuildEnvHash /
  # computeToolchainSalt: `nim --version` once per process) already make.
  # Only the digest COMPUTATION is cached: every read still compares the
  # manifest headers against it (per-read revalidation,
  # verification_dag_contract.md §5), a resolved-path change recomputes, and
  # failed computations are never cached (per-call fail-closed). This is not
  # closure or manifest memoization — the VS-T no-memoization rule governs
  # the closure recomputed from live manifest + file content, which is
  # untouched.
  ToolchainIdentity = object
    nimExe: string          ## resolved binary path the digest came from
    sha256: string          ## sha256 of the nim binary bytes
    versionEscaped: string  ## full `nim --version` output, \n-escaped, stripped
    valid: bool

var cachedToolchainIdentity {.threadvar.}: ToolchainIdentity

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func parseManifest(content: string): ManifestParse {.raises: [].} =
  ## Strict parse: KEY=VAL identity headers, then CLOSURE:/PROBE: payload
  ## lines. Any unexpected line shape leaves the parse incomplete
  ## (callers treat an incomplete parse as invalid — fail-closed).
  result = ManifestParse(closure: @[], probes: @[])
  var headerDone = false
  for raw in content.splitLines():
    if raw.len == 0:
      continue
    if raw.startsWith("CLOSURE:"):
      headerDone = true
      result.closure.add(raw[8 ..^ 1])
    elif raw.startsWith("PROBE:"):
      headerDone = true
      result.probes.add(raw[6 ..^ 1])
    elif not headerDone and "=" in raw:
      let key = raw[0 ..< raw.find('=')]
      let val = raw[raw.find('=') + 1 ..^ 1]
      case key
      of "SCHEMA": result.schema = val
      of "MAIN": result.main = val
      of "NIM_SHA256": result.nimSha = val
      of "NIM_VERSION": result.nimVersion = val
      of "FLAGS": result.flags = val
      of "CWD_CONTRACT": result.cwdContract = val
      else:
        # Unknown header — a foreign producer; refuse the manifest.
        result.schema = ""
        return
    else:
      # Malformed line (header after payload, junk) — refuse.
      result.schema = ""
      return

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc loadProjectClosure*(sourcePath: string): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compiler-truth project closure for a gate main module, or @[] (no
  ## closure — caller must treat as Unresolved/""). Validation is total:
  ## schema, MAIN binding, CWD contract, FLAGS profile, toolchain identity,
  ## project-file filter, structural freshness (every project closure file
  ## must exist) and live probe binding. Single-exit contract: files are
  ## collected into a local and assigned to the result ONLY after every
  ## check passes — no partial closure can leak through a failed
  ## validation (fail-closed, §0.9).
  result = @[]
  if sourcePath.len == 0 or not fileExists(sourcePath):
    return
  var cwd = ""
  try:
    cwd = getCurrentDir()
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  if cwd.len == 0:
    return
  let absMain =
    if isAbsolute(sourcePath): normalizedPath(sourcePath)
    else: normalizedPath(cwd / sourcePath)
  # Deterministic repository root for an in-repo absolute path: nearest
  # ancestor carrying the .axiom_root anchor (axiom.toml legacy fallback).
  # Deliberately NOT AXIOM_ROOT-driven (core/utils/repo_root env seam):
  # CAS identity must depend on the file's actual location, not the
  # environment. Empty when no anchor is found (fail-closed).
  var repoRoot = ""
  block repoRootResolution:
    try:
      var cur = absMain.parentDir()
      for _ in 0..10:
        if cur.len == 0:
          break
        if fileExists(cur / ".axiom_root") or fileExists(cur / "axiom.toml"):
          repoRoot = cur
          break
        let parent = cur.parentDir()
        if parent == cur:
          break
        cur = parent
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  if repoRoot.len == 0:
    logInfo("closure_manifest", "no repo root anchor for " & absMain & " — no closure (fail-closed)")
    return
  let manifestPath = repoRoot / ManifestDirRel / (absMain.splitFile().name & ".manifest")
  let contentRes = readFileOpt(manifestPath)
  if contentRes.isErr:
    logInfo("closure_manifest", "manifest missing/unreadable for " & absMain &
      " (" & manifestPath & ") — no closure (fail-closed; run bin/precompile_gates)")
    return
  let content = contentRes.get()
  let m = parseManifest(content)
  if m.schema != ManifestSchema:
    logInfo("closure_manifest", "manifest schema mismatch for " & absMain & " — no closure (fail-closed)")
    return
  if m.main != absMain or m.cwdContract != CwdContractToken:
    logInfo("closure_manifest", "manifest MAIN/CWD-contract mismatch for " & absMain & " — no closure (fail-closed)")
    return
  if m.flags != genDependProfile(repoRoot):
    logInfo("closure_manifest", "manifest FLAGS profile mismatch for " & absMain &
      " — no closure (fail-closed; regenerate manifests)")
    return
  if m.closure.len == 0:
    logInfo("closure_manifest", "manifest has empty closure for " & absMain & " — no closure (fail-closed)")
    return
  var files: seq[string] = @[]
  var mainSeen = false
  for p in m.closure:
    if not isAbsolute(p):
      logInfo("closure_manifest", "relative closure line in manifest for " & absMain & " — no closure (fail-closed)")
      return
    if not p.startsWith(repoRoot & "/"):
      continue  # stdlib/nimble resolution — outside the project, filtered out
    if normalizedPath(p) != p:
      logInfo("closure_manifest", "non-normalized closure line in manifest for " & absMain & " — no closure (fail-closed)")
      return
    if p == absMain:
      mainSeen = true
    if not fileExists(p):
      logInfo("closure_manifest", "closure file vanished: " & p & " — no closure (fail-closed; regenerate manifests)")
      return
    files.add(p)
  if not mainSeen:
    logInfo("closure_manifest", "manifest closure does not contain the main module " & absMain & " — no closure (fail-closed)")
    return
  # Toolchain identity — the manifest is only trustworthy under the nim
  # that produced it: nim binary sha256 + full `nim --version` output
  # (newlines escaped as literal \n, exactly as the generator writes it);
  # empty/failed identity → manifest rejected. The digest is computed once
  # per process and compared on every read (cachedToolchainIdentity —
  # DEBT#522 remaining half, 2026-11-10; see the type comment). Inlined at
  # the call site per the module's two-proc I/O surface contract (ratchet
  # 952 in architecture_invariants.nim).
  let nimExe = try: findExe("nim") except CatchableError: ""
  var identityOk = false
  if nimExe.len > 0:
    if cachedToolchainIdentity.valid and cachedToolchainIdentity.nimExe == nimExe:
      identityOk = cachedToolchainIdentity.sha256 == m.nimSha and
                   cachedToolchainIdentity.versionEscaped == m.nimVersion
    else:
      try:
        let binRes = readFileOpt(nimExe)
        let (outp, code) = execCmdEx(quoteShell(nimExe) & " --version")
        if binRes.isOk and code == 0:
          let sha = hash_kernel.sha256Hex(binRes.get())
          let ver = outp.replace("\n", "\\n").strip()
          cachedToolchainIdentity = ToolchainIdentity(
            nimExe: nimExe, sha256: sha, versionEscaped: ver, valid: true)
          identityOk = sha == m.nimSha and ver == m.nimVersion
      except CatchableError:
        discard  # axiom:best-effort(ioboundary catch) — identity unknown
  if not identityOk:
    logInfo("closure_manifest", "toolchain identity mismatch for " & absMain &
      " — no closure (fail-closed; regenerate manifests)")
    return
  # Probe binding (quirk 4): existing probe targets are real compile inputs
  # from the present branch — their content joins the hashed set.
  for pr in m.probes:
    if not isAbsolute(pr):
      logInfo("closure_manifest", "relative probe line in manifest for " & absMain & " — no closure (fail-closed)")
      return
    if fileExists(pr) and pr.startsWith(repoRoot & "/") and pr notin files:
      files.add(pr)
  files.sort(cmp)
  result = files

{.pop.}
