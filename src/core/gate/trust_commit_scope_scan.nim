import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Trust Commit Scope Scanner (I7) — authority-based, sink-centric, TARGET-based.
##
## Under the Trust Commit Architecture, the I7 invariant protects *authoritative
## trust-state transitions*, not individual file writes:
##
##   "No Trust Durable State may be persisted except through TrustCommit."
##
## The scanner does NOT flag every raw writeFile/moveFile. It only flags a raw
## persistence effect when its write TARGET is an AUTHORITATIVE trust
## representation (the journal: "data/trusted/journal") and the write is not
## routed through the TrustCommit closure (C). Derived certificate / cache /
## transient / sandbox writes are OUT of the I7 universe by construction (see
## trust_authority_spec).
##
##   I7-A  Semantic authority — a raw authoritative-representation write outside
##         the closure is a DIRECT_TRUST_WRITE finding.
##   I7-B  Persistence escape  — any raw persistence effect that mutates an
##         authoritative representation is a finding (same detection as I7-A,
##         asserted at the raw-sink level).
##   I7-1  Closed world        — a trust-relevant durable write whose TARGET
##         class cannot be resolved (decUnknown) fails closed.
##
## DEBT#471: the durable-effect class is derived from the extracted write
## TARGET expression, never from whole-line prose — a comment word ("cache",
## "journal") is not evidence about the target. Closure routing is import-aware:
## an unqualified allowlisted call in a file that imports the provider module
## (e.g. bare `writeFileOpt(…)` under `import core/utils/io_utils`) counts as
## routed through the closure.
##
## Classification of the write target is delegated to
## core/trusted/trust_authority_spec.nim (durableEffectClassOf / authoritative
## representation SSOT) — no filesystem-path heuristics are hardcoded here.
##
## Line numbers are REAL: iteration uses `for idx, line in lines:` and reports
## idx + 1 (1-based). The prior manual `inc idx` inside the finding branch was a
## defect that produced wrong line numbers.
##
## This module also owns the gate's scan-scope SSOT (resolveScanScope) and the
## judgment-input closure digest (judgmentClosureDigest) consumed by the memo
## key layer so the memo binds exactly what the runner scans (DEBT#471).

import std/os
import std/strutils
import std/sequtils
import core/results
import core/crypto/hash_kernel
import core/gate/git_snapshot  # stagedTreeOid — staged-index axis for the judgment closure (DEBT#471)
import core/utils/io_utils
import core/utils/repo_root
import core/axiom_pragmas
import core/trusted/trust_authority_spec

# ---------------------------------------------------------------------------
# Public types and manifest
# ---------------------------------------------------------------------------

const TrustCommitScopeGateId* = "trust-commit-scope"
  ## Single SSOT for the gate id string. The memo key layer
  ## (gate/orchestrator/hook/memo.nim) binds this gate's judgment closure by
  ## dispatching on this id — the literal lives only here.

type
  WriteFinding* = tuple[file: string, line: int, call: string]

## Symbols that constitute valid routing THROUGH the TrustCommit closure (C).
## A raw persistence effect co-located with one of these on the same line is
## considered routed, hence inside the allowed authority path. This list mirrors
## the declared authority root (`trust_commit.commitVerification`) and its
## append/journal helpers.
const allowedWriterSymbols*: seq[string] = @[
  "append_store.writeRecord",
  "append_store.appendRecord",
  "claim_store_append.appendClaim",
  "claim_store_append.appendSolverInvocation",
  "trust_commit.commitVerification",
  "trust_commit.commitCertificateVerification",
  "trust_commit.commitJsonVerification",
  "io_utils.writeFileAtomic",
  "io_utils.writeFileOpt",
  "stdlib_shield.safeMoveFile",
  "posix.fsync",
  "writeGlobalSymbolGraphSnapshot",
  "writeFileAtomic",                     ## proof_universe_commit legacy routing
]

## Raw persistence effects that the I7-B escape detector watches. If such an
## effect's target is an authoritative representation (journal) and the line is
## not routed through the closure, it is a finding.
const rawPersistencePatterns*: seq[string] = @[
  "writeFile(",
  "writeFileOpt(",
  "writeFileSafe(",
  "writeFileAtomic(",
  "moveFile(",
  "moveFileOpt(",
  "renameFile(",
  "fmWrite",
]

## Trust-state vocabulary that marks a write as authoritative-trust-relevant for
## closed-world classification. Writes referencing only DERIVED vocabulary
## (certificate/vault) are exempt from I7-A; they are caught by the closed-world
## check only if they cannot be resolved to a known non-authoritative class.
const authoritativeVocabulary*: seq[string] = @[
  "data/trusted/journal",
  "data/trusted/",
  "journal",
]

# ---------------------------------------------------------------------------
# Classification (delegated to trust_authority_spec where possible)
# ---------------------------------------------------------------------------

## DEBT#471: classification is TARGET-based. The prior line-based classifier
## read the WHOLE source line, so a comment word ("cache", "journal") could
## flip the durable-effect class of an unrelated write. That produced a dormant
## false positive at src/verification/vault_index.nim:124 — disarmed only while
## its best-effort comment happened to contain the word "cache", re-arming the
## moment the comment was reworded. The class is now derived from the write
## TARGET expression only; authorial prose on the line is not evidence.
func classifyWriteTarget(target: string): DurableEffectClass {.raises: [].} =
  if isAuthoritativeRepresentation(target):
    decAuthoritative
  elif isDerivedRepresentation(target):
    decDerived
  elif target.contains("sandbox"):
    decSandbox
  elif target.contains("temp") or target.contains(".tmp") or target.contains("/tmp") or
       target.contains("lean_build") or target.contains("z3"):
    decTransient
  elif target.contains("cache") or target.contains(".cache") or target.contains("cas"):
    decCache
  else:
    decUnknown

func extractWriteTarget(line: string; call: string): string {.raises: [].} =
  ## Best-effort extraction of the write TARGET: the first argument expression
  ## of the flagged call. Falls back to the first parenthesised call's first
  ## argument on the line (fmWrite is an `open(…, fmWrite)` argument, not a
  ## call). Returns "" when no target expression can be isolated.
  func firstArgAfter(openPos: int; line: string): string {.raises: [].} =
    try:
      var i = openPos + 1
      var depth = 1
      var inStr = false
      while i < line.len and (i - openPos) < 240:
        let c = line[i]
        if inStr:
          if c == '"': inStr = false
          result.add(c)
        else:
          case c
          of '"':
            inStr = true
            result.add(c)
          of '(', '[', '{':
            depth.inc
            result.add(c)
          of ')', ']', '}':
            depth.dec
            if depth == 0: break
            result.add(c)
          of ',':
            if depth == 1: break
            result.add(c)
          else:
            result.add(c)
        inc i
      result = result.strip()
    except IndexDefect:
      result = ""
  let marker = call & "("
  let start = line.find(marker)
  if start >= 0:
    return firstArgAfter(start + marker.len - 1, line)
  let openPos = line.find('(')
  if openPos >= 0:
    result = firstArgAfter(openPos, line)
  else:
    result = ""

func isDirectWriteLine(line: string): bool =
  for pat in rawPersistencePatterns:
    if line.contains(pat):
      return true
  false

## Leaf module names imported by a file (e.g. `import core/utils/io_utils` →
## "io_utils"). Nim resolves an unqualified call against the module's import
## set, so an unqualified `writeFileOpt(…)` in a file that imports io_utils IS
## io_utils.writeFileOpt — the qualified allowlist entry. Reading the import
## block is what lets allowlist matching stay honest without wildcarding every
## bare symbol name in the codebase. Only the top-of-file import block is read;
## scanning stops at the first non-import statement.
func extractImportedModules(content: string): seq[string] {.raises: [].} =
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"):
      continue
    var tail = ""
    var isFromImport = false
    if line.startsWith("import "):
      tail = line["import ".len .. ^1]
    elif line.startsWith("from "):
      tail = line["from ".len .. ^1]
      isFromImport = true
    else:
      break
    if isFromImport:
      # `from a/b/c import sym1, sym2` — only the leading path names a module.
      let tokens = tail.split({',', ' ', '[', ']'})
      if tokens.len > 0 and tokens[0].strip().len > 0:
        let leaf = tokens[0].strip().split('/')[^1]
        if leaf.len > 0:
          result.add(leaf)
      continue
    for token in tail.split({',', ' ', '[', ']'}):
      var seg = token.strip()
      if seg.len == 0:
        continue
      if seg == "except":
        break
      let asPos = seg.find(" as ")
      if asPos > 0:
        seg = seg[0 ..< asPos].strip()
      if seg.len == 0 or seg.contains('(') or seg.contains('#'):
        continue
      let leaf = seg.split('/')[^1]
      if leaf.len > 0:
        result.add(leaf)

func isAllowedLine(line: string; importedModules: seq[string]): bool =
  for sym in allowedWriterSymbols:
    if line.contains(sym):
      return true
    let dotPos = sym.find('.')
    if dotPos > 0:
      let provider = sym[0 ..< dotPos]
      let leaf = sym[(dotPos + 1) ..< sym.len]
      if provider in importedModules and line.contains(leaf):
        return true
  false

## Does the write TARGET reference authoritative trust-state vocabulary
## (journal / trusted/)? Applied to the extracted target expression, not the
## whole line — a comment may not classify a write it does not denote (DEBT#471).
func referencesAuthoritativeState(target: string): bool =
  for v in authoritativeVocabulary:
    if target.contains(v):
      return true
  false

func writeCallOnLine(line: string): string =
  ## Return the first raw-persistence call token present on the line.
  for pat in rawPersistencePatterns:
    if line.contains(pat):
      return pat.strip(trailing = true, chars = {'('})
  ""

# ---------------------------------------------------------------------------
# Scan-scope SSOT + judgment-input closure (DEBT#471)
# ---------------------------------------------------------------------------

func commonAncestorDir*(dirs: seq[string]): string {.raises: [].} =
  ## Longest common directory-component prefix of `dirs`. Returns "" when the
  ## dirs share no component (repo-root level span). Pure: string ops only.
  if dirs.len == 0:
    return ""
  var components: seq[seq[string]] = @[]
  for d in dirs:
    components.add(d.split('/'))
  var prefix = components[0]
  for comps in components[1 .. ^1]:
    var keep = 0
    let limit = min(prefix.len, comps.len)
    while keep < limit and prefix[keep] == comps[keep]:
      inc keep
    prefix.setLen(keep)
    if prefix.len == 0:
      break
  if prefix.len == 0:
    return ""
  prefix.join("/")

proc resolveScanScope*(repoRoot: string; stagedFiles: seq[string]): string {.raises: [].} =
  ## Single SSOT for trust-commit-scope scan-scope resolution. The gate runner
  ## and the memo key layer MUST resolve the same scope — the runner scans it,
  ## the memo binds it into the cache key. Policy: the judgment scope is the
  ## common ancestor directory of the changed/staged files (every directory
  ## this run judges, not merely the first file's parent — a single-parent
  ## scope lets violations in sibling staged dirs escape, observed as a hollow
  ## PASS in DEBT#471 evidence). When the changed set spans repo-root level,
  ## the scope caps at the I7 universe <repoRoot>/src. With no changed files,
  ## fall back to <repoRoot>/src, then repo-root discovery. Returns "" if no
  ## directory can be determined (infrastructure absence).
  var dirs: seq[string] = @[]
  for f in stagedFiles:
    let parent = f.splitFile().dir
    if parent.len > 0 and dirExists(parent) and parent notin dirs:
      dirs.add(parent)
  if dirs.len > 0:
    if dirs.len == 1:
      return dirs[0]
    let common = commonAncestorDir(dirs)
    if common.len > 0 and common != "." and dirExists(common):
      return common
    # Repo-root-level span: cap at the I7 universe instead of scanning the
    # whole worktree (data/, build/, bin/ are outside the judgment universe).
    if repoRoot.len > 0 and dirExists(repoRoot / "src"):
      return repoRoot / "src"
  if repoRoot.len > 0 and dirExists(repoRoot / "src"):
    return repoRoot / "src"
  try:
    let root = findRepoRoot()
    if root.len > 0 and dirExists(root / "src"):
      return root / "src"
  except CatchableError:  # axiom:best-effort("best-effort root discovery; infra absent -> fail-closed closure below")
    discard
  ""

proc judgmentClosureDigest*(repoRoot: string; stagedFiles: seq[string]): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Digest of the trust-commit-scope gate's judgment-input closure (DEBT#471):
  ## scan scope (resolveScanScope) + staged-index axis (git write-tree OID).
  ## The scanner reads the worktree under `scope`; the staged axis pins which
  ## index state produced the run — together they make a FAIL under one closure
  ## non-replayable under another. Returns "" when the scope cannot be resolved
  ## — consumers MUST fail closed (no cache key, forced execution).
  let scope = resolveScanScope(repoRoot, stagedFiles)
  if scope.len == 0:
    return ""
  let treeOid = stagedTreeOid(repoRoot)
  sha256Hex(TrustCommitScopeGateId & "|closure|" & scope & "|" & treeOid)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

proc scanForDirectWrites*(dir: string): Result[seq[WriteFinding], string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], axiomDecision(id = "DECISION-0643", reason = "Authority-based I7 scan: flag raw persistence effects whose write TARGET is an authoritative trust representation (data/trusted/journal) that is not routed through the TrustCommit closure, plus unclassifiable durable writes whose TARGET references authoritative trust vocabulary; target-based classification and import-aware allowlist routing per DEBT#471; fail-closed on missing dir, empty result on clean scan", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v33").} =
  ## Authority-based I7 scan over all .nim files under `dir`.
  ##
  ## Sink-centric and TARGET-based: only writes whose target expression (a)
  ## denotes an authoritative representation and are not closure-routed, or
  ## (b) are durable writes whose target class cannot be resolved (I7-1
  ## decUnknown) while the target itself references authoritative trust
  ## vocabulary, are reported. Derived / transient / sandbox / cache targets
  ## never enter the I7 universe. Closure routing is import-aware: an
  ## unqualified allowlisted call in a file that imports the provider module
  ## counts as routed (DEBT#471).
  if not dirExists(dir):
    return err("trust_commit_scope_scan: directory does not exist: " & dir)
  var allFindings: seq[WriteFinding] = @[]
  for path in walkDirRec(dir):
    if not path.endsWith(".nim"):
      continue
    let content = readFile(path)
    let lines = content.splitLines()
    let importedModules = extractImportedModules(content)
    for idx, line in lines:
      if not isDirectWriteLine(line) or isAllowedLine(line, importedModules):
        continue
      let call = writeCallOnLine(line)
      let target = extractWriteTarget(line, call)
      let cls = classifyWriteTarget(target)
      if cls == decAuthoritative:
        # I7-A / I7-B: raw authoritative-representation write outside closure.
        allFindings.add((file: path, line: idx + 1, call: call))
      elif cls == decUnknown and referencesAuthoritativeState(target):
        # I7-1 closed-world: trust-relevant durable write, class unresolved.
        allFindings.add((file: path, line: idx + 1, call: call))
  ok(allFindings)

{.pop.}
