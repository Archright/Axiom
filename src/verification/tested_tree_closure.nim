import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## tested_tree_closure.nim — the TESTED-TREE (M) test-source closure
## derivation for the judgment key (contract §4, v1.0.5 — components ① and ③).
##
## What this module is:
##   The closure of a subject's test source, derived from the TESTED tree's
##   git objects — NEVER from the working directory. The derivation is a pure
##   function of (M's tree, the subject's entry paths, the subject's fixture
##   paths), so the plan stage (lane) and the attest stage derive the SAME
##   closure from the SAME tree, whatever their working directories are.
##
## What changed in v5 (and why):
##   v4's ① was `computeTransitiveHash(testPath, ".")` — a WORKDIR-relative,
##   ONE-HOP walk (core/gate/transitive_hash.nim). Package-style imports
##   (`import core/types/results`) did not resolve at all, so the measured
##   closure was 19 files with depth ≥ 2 = 0 — the identity did not cover the
##   sources the judged test actually compiles. v5 walks the closure from the
##   TESTED TREE, resolving package-style imports against the compiler's own
##   search roots, multi-hop, cycle-safe — the honest closure.
##
## The dependency rule (R-NT) — every import is classified:
##   (a) TREE PATH      — the import resolves to a path in M's tree; the
##                        path's BLOB OID is a closure input.
##   (b) PINNED EXTERNAL— the import resolves to a nimble package (or to a
##                        compiler-shipped module covered by nimble.lock's
##                        "nim" entry). The lock entry's identity
##                        (name · version · vcsRevision · checksums.sha1) is
##                        recorded as a closure input; the entry MUST exist in
##                        M's own nimble.lock.
##   (c) BUILD-GENERATED— the module is not in M (it is produced by the build).
##                        Admissible ONLY when every value it contributes is
##                        bound — the committed template's blob is a tree
##                        member (its constants are tree-bound) and the
##                        executor build-provenance values are bound by the
##                        executor's generation identity (contract RR-6).
##                        Otherwise the closure is NOT reusable.
##   (d) UNRESOLVED    — neither (a), (b) nor (c): unresolvable AND unpinned.
##                        The closure is NOT reusable (the caller falls back to
##                        EXECUTED — a "skipped unpinned dependency" never
##                        grants a REUSED).
##   Every (b)/(c)/(d) hit is RECORDED — never silently skipped.
##
## The stdlib class (`std/**`, `system`, `nimsuggest/**`) is not a closure
## input: it is compiler-shipped and bound by component ⑧ (the compiler pin).
## Single-word tokens are NOT assumed to be stdlib — a single-word nimble
## package (`ed25519`) is a (b) hit, decided by M's lock, not by the token's
## shape.
##
## The import walk uses the Nim AST (core/parser_utils.parseStringAST over
## compiler/parser) — a line parser mis-reads comments and string literals
## (a `# ... import x` comment or a docstring mentioning `import` would enter
## the closure; a real import inside a string would not).
##
## The ⑤ derivation authority (verification/semantic_set_derivation.nim) is
## REUSED, never extended: this module consumes its git boundary
## (listTreeUniverse), its record canonicalization (TreeElement ·
## elementRecord) and its digest (semanticDigestFromRecords). The single
## derivation authority for the semantic set stays that module.

import std/[algorithm, json, osproc, sets, streams, strutils, tables]
import compiler/ast
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/parser_utils
import core/results
import verification/semantic_set_derivation

axiomIoBoundary()

# ---------------------------------------------------------------------------
# Constants — the resolution surface
# ---------------------------------------------------------------------------

const
  ClosureTreeRoots*: array[5, string] = ["src", "tools", ".", "tests/gateway",
    "src/shared_types"]
    ## The compiler's module search roots INSIDE the tested tree — the mirror
    ## of config.nims's own `switch("path", "src"/"tools")` pair plus
    ## config/paths.nims's set (`.` · `src` · `tests/gateway` ·
    ## `src/shared_types` · `tools`). The compiler resolves a package-style
    ## import against the FIRST root that holds the module
    ## (compiler/options.nim findModule → findFile), so the closure must
    ## search the same roots — a closure that resolved fewer roots than the
    ## compiler would under-measure the judged sources.
  StdlibPrefixes*: array[3, string] = ["std/", "nimsuggest/", "system/"]
    ## The compiler-shipped standard library — bound by component ⑧ (the
    ## compiler pin), not a closure input.
  CompilerShippedPrefix* = "compiler/"
    ## The compiler's own modules (compiler/ast · compiler/parser · …) — the
    ## "nim" entry of M's nimble.lock pins them (R-NT (b)).
  NimbleLockPath* = "nimble.lock"
    ## The lock file — read from M's TREE (never the workdir). It is both a
    ## semantic-set carve-out (⑤ — a normative exact path) and a recipe
    ## member (⑦), so a pin change already advances the key; the pin
    ## identity recorded here is a narrowing-only RECORD of which lock entry
    ## the reuse rests on.

type
  BuildGeneratedModule* = object
    ## One build-generated module (R-NT (c)) — absent from M, produced by the
    ## build. `templatePath` is the COMMITTED template whose blob IS a tree
    ## member: the tree-bound constants of the generated module are bound by
    ## that blob. `provenanceSymbols` are the values the build SUBSTITUTES
    ## (the executor's build provenance) — they are bound by the executor's
    ## generation identity, deliberately NOT by the closure wire (contract
    ## v1.0.4 p2: a tree OID enters nowhere — binding them would re-introduce
    ## the over-invalidation v1.0.4 removed).
    token*: string             ## the import token, e.g. "generated/build_env"
    templatePath*: string      ## the committed template (a tree member)
    symbols*: seq[string]      ## the module's exported symbol set (the drift guard)
    provenanceSymbols*: seq[string] ## the executor-bound subset of `symbols`
    boundBy*: string           ## the binding ground (recorded in the decision file)

const
  BuildGeneratedModules*: array[1, BuildGeneratedModule] = [
    BuildGeneratedModule(
      token: "generated/build_env",
      templatePath: "src/generated/build_env.nim.default",
      symbols: @["BuildEnvZ3Version", "BuildEnvCommitCount", "BuildEnvGitHash",
        "BuildEnvBuildDate", "BuildEnvLeanSourceHash", "BuildSourceHash",
        "VerifierBuildId", "VerifierBuildSourceHash", "BuildEnvProjectRoot"],
      provenanceSymbols: @["BuildEnvCommitCount", "BuildEnvGitHash",
        "BuildEnvBuildDate", "BuildEnvLeanSourceHash", "BuildSourceHash",
        "VerifierBuildId", "VerifierBuildSourceHash", "BuildEnvProjectRoot"],
      boundBy: "tree-bound: the template blob src/generated/build_env.nim.default " &
        "is a closure member (BuildEnvZ3Version is additionally bound by ⑧ " &
        "compilerPins' Z3 pin); executor-bound: the substituted build-provenance " &
        "values are bound by the executor's generation identity (④ toolchain + " &
        "the trusted-writer-set/epoch pin), deliberately not by the closure " &
        "wire — contract RR-6")]
    ## The single build-generated module the judged closures reach. Its
    ## generated form (src/generated/build_env.nim) is gitignored — it is in
    ## NO tree; the committed template is. The symbol set is DECLARED here and
    ## the template's own exports are compared against it on every derivation
    ## (drift guard): a new constant that nobody declared makes the closure
    ## non-reusable until the declaration is updated.

# ---------------------------------------------------------------------------
# Types
# ---------------------------------------------------------------------------

type
  DependencyClass* = enum
    dcTreeMember,     ## (a) — resolved to a path in the tested tree
    dcPinnedExternal, ## (b) — pinned by an entry of M's nimble.lock
    dcBuildGenerated, ## (c) — build-generated (absent from M)
    dcUnresolved      ## (d) — unresolvable and unpinned
    dcStdlib          ## the compiler-shipped stdlib class — bound by ⑧

  ClosureDependency* = object
    ## One classified import of the closure.
    rawImport*: string       ## the import token as written
    importer*: string        ## the tree path of the importing module
    klass*: DependencyClass
    treePath*: string        ## (a): the resolved tree path
    blobOid*: string         ## (a): the resolved blob's OID
    pinName*: string         ## (b): the lock entry's name
    note*: string            ## the binding ground / the reason

  TestedTreeClosure* = object
    ## The full derivation outcome.
    members*: seq[TreeElement]      ## (a) — the closure's tree members
    dependencies*: seq[ClosureDependency] ## every classified import
    notes*: seq[string]             ## every (b)/(c)/(d) hit — recorded, never silent
    nonReusable*: seq[string]       ## the (c)/(d) hits that forbid reuse
    sourceDigest*: string           ## ① — the closure's digest
    fixturesDigest*: string         ## ③ — the fixture set's digest
    pinIdentity*: string            ## the narrowing-only pin record
    probeTreeOid*: string           ## the probe anchor (out-of-key — provenance)

# ---------------------------------------------------------------------------
# Pure helpers — path + AST
# ---------------------------------------------------------------------------

func normalizeTreePath*(path: string): string {.raises: [].} =
  ## A repo-relative POSIX path with "." / ".." segments collapsed.
  var parts: seq[string] = @[]
  for seg in path.split('/'):
    if seg.len == 0 or seg == ".":
      continue
    if seg == "..":
      if parts.len > 0:
        parts.setLen(parts.len - 1)
    else:
      parts.add(seg)
  parts.join("/")

func treeDirOf*(path: string): string {.raises: [].} =
  ## The directory part of a repo-relative path ("" at the root).
  let i = path.rfind('/')
  if i < 0: "" else: path[0 ..< i]

func isStdlibToken*(token: string): bool {.raises: [].} =
  ## The compiler-shipped stdlib class — bound by component ⑧, not a closure
  ## input. A single-word token is NOT assumed to be stdlib: a single-word
  ## nimble package is a (b) hit, decided by M's lock, not by the token's
  ## shape (the v4 line parser's heuristic mis-read `ed25519` as stdlib).
  for p in StdlibPrefixes:
    if token.startsWith(p):
      return true
  token == "system"

func importModulePaths*(node: PNode): seq[string] {.raises: [].} =
  ## The module path(s) an import child node denotes. The Nim AST encodes a
  ## package path as an nkInfix tree over "/" (`a/b/c`), a bracketed group as
  ## nkBracket (`std/[a, b]`), the deprecated dotted form as nkDotExpr, and
  ## an alias as an nkInfix over "as" (the parser's nkImportAs path is
  ## disabled in 2.2.10 — parser.nim's `when false` block — so the alias
  ## arrives as an infix expression).
  if node.isNil:
    return
  case node.kind
  of nkIdent:
    result.add(node.ident.s)
  of nkInfix:
    if node.len < 3:
      return
    let op = if node[0].kind == nkIdent: node[0].ident.s else: ""
    if op == "/":
      for l in importModulePaths(node[1]):
        for r in importModulePaths(node[2]):
          result.add(l & "/" & r)
    elif op == "as":
      result = importModulePaths(node[1])
  of nkBracket:
    for c in node:
      result.add(importModulePaths(c))
  of nkPrefix:
    # A relative module path segment (`../../src/...`) parses as a PREFIX
    # expression — the operator is the `..`-segment ident and the operand is
    # the rest of the path (the compiler renders the whole tree).
    if node.len >= 2 and node[0].kind == nkIdent:
      let op = node[0].ident.s
      for rest in importModulePaths(node[1]):
        result.add(op & rest)
  of nkDotExpr:
    if node.len >= 2 and node[0].kind == nkIdent and node[1].kind == nkIdent:
      result.add(node[0].ident.s & "/" & node[1].ident.s)
  else:
    discard

func importTokensOf*(node: PNode): seq[string] {.raises: [].} =
  ## Every module token the AST of one source declares.
  if node.isNil:
    return
  case node.kind
  of nkImportStmt:
    for c in node:
      result.add(importModulePaths(c))
  of nkFromStmt:
    if node.len > 0:
      result.add(importModulePaths(node[0]))
  else:
    for c in node:
      result.add(importTokensOf(c))

func declaredName*(node: PNode): string {.raises: [].} =
  ## The declared name of a definition head — the export marker (`*`) makes
  ## the head an nkPostfix over the name, and a pragma-wrapped head an
  ## nkPragExpr.
  if node.isNil:
    return
  case node.kind
  of nkIdent:
    node.ident.s
  of nkPostfix:
    if node.len > 0: declaredName(node[^1]) else: ""
  of nkPragmaExpr:
    if node.len > 0: declaredName(node[0]) else: ""
  else:
    ""

func exportedConstNames*(node: PNode): seq[string] {.raises: [].} =
  ## The names a source's top-level const section exports — the symbol set a
  ## build-generated module contributes (the drift guard).
  if node.isNil:
    return
  if node.kind == nkConstSection:
    for c in node:
      if c.kind == nkConstDef and c.len > 0:
        let name = declaredName(c[0])
        if name.len > 0:
          result.add(name)
    return
  for c in node:
    result.add(exportedConstNames(c))

# ---------------------------------------------------------------------------
# I/O boundary — git objects only (the workdir is never read)
# ---------------------------------------------------------------------------

proc readBlobs*(repoRoot: string; oids: seq[string]): Result[Table[string, string], string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read many blobs in ONE git subprocess (`git cat-file --batch`) — the
  ## content identity comes from the git object store, never from the working
  ## directory. A missing object is an error (fail-closed), never an empty
  ## content.
  var blobsOut = initTable[string, string]()
  if oids.len == 0:
    return ok(blobsOut)
  var p: Process
  try:
    p = startProcess("git", workingDir = repoRoot,
      args = ["cat-file", "--batch"], options = {poUsePath})
  except CatchableError as e:
    return err("tested_tree_closure: git cat-file spawn failed (fail-closed): " & e.msg)
  var raw = ""
  try:
    for o in oids:
      p.inputStream.write(o & "\n")
    p.inputStream.close()
    raw = p.outputStream.readAll()
  except CatchableError as e:
    try:
      p.close()
    except CatchableError:
      discard # axiom:best-effort(capture already failed; the derivation errs regardless)
    return err("tested_tree_closure: git cat-file capture failed (fail-closed): " & e.msg)
  let code = p.waitForExit()
  p.close()
  if code != 0:
    return err("tested_tree_closure: git cat-file --batch failed (fail-closed, exit " &
      $code & ")")
  var pos = 0
  while pos < raw.len:
    let nl = raw.find('\n', pos)
    if nl < 0:
      break
    let header = raw[pos ..< nl]
    pos = nl + 1
    let parts = header.split(' ')
    if parts.len < 3:
      return err("tested_tree_closure: malformed cat-file header '" & header &
        "' (fail-closed)")
    let oid = parts[0]
    let kind = parts[1]
    var size = 0
    for ch in parts[2]:
      if ch < '0' or ch > '9':
        return err("tested_tree_closure: malformed cat-file size '" & parts[2] &
          "' (fail-closed)")
      size = size * 10 + (ord(ch) - ord('0'))
    if kind == "missing":
      return err("tested_tree_closure: git object missing (fail-closed): " & oid)
    if pos + size > raw.len:
      return err("tested_tree_closure: truncated cat-file payload (fail-closed): " & oid)
    blobsOut[oid] = raw[pos ..< pos + size]
    pos += size
    if pos < raw.len and raw[pos] == '\n':
      inc pos
  ok(blobsOut)

proc readBlob*(repoRoot, oid: string): Result[string, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## One blob's bytes from the git object store.
  let blobs = readBlobs(repoRoot, @[oid])
  if blobs.isErr:
    return err(blobs.error)
  if not blobs.get.hasKey(oid):
    return err("tested_tree_closure: git object absent from the batch read (fail-closed): " & oid)
  ok(blobs.get[oid])

# ---------------------------------------------------------------------------
# Resolution — the compiler's own order (compiler/options.nim findModule)
# ---------------------------------------------------------------------------

func resolveTreePath*(token, importerPath: string;
    byPath: Table[string, TreeElement]): string {.raises: [].} =
  ## The tree path a module token resolves to, or "" when it resolves to
  ## nothing inside the tested tree. The compiler's order: the IMPORTING
  ## file's own directory first, then the configured search roots; a token
  ## that starts with "." is strictly relative to the importing file (the
  ## compiler never falls back to the search roots for it).
  var base = token
  if not base.endsWith(".nim"):
    base = base & ".nim"
  var candidates: seq[string] = @[]
  if token.startsWith("."):
    candidates.add(normalizeTreePath(treeDirOf(importerPath) & "/" & base))
  else:
    candidates.add(normalizeTreePath(treeDirOf(importerPath) & "/" & base))
    for root in ClosureTreeRoots:
      candidates.add(normalizeTreePath(root & "/" & base))
  for c in candidates:
    if byPath.hasKey(c):
      return c
  ""

func lockEntryName*(token: string; lockPackages: Table[string, JsonNode]): string {.
    raises: [].} =
  ## The nimble.lock entry that pins a module token (R-NT (b)), or "" when no
  ## entry pins it. The compiler's own modules are covered by the "nim"
  ## entry; every other package is named by its FIRST path segment.
  if token.startsWith(CompilerShippedPrefix):
    return "nim"
  let first = token.split('/')[0]
  if lockPackages.hasKey(first):
    return first
  ""

func lockEntryIdentity*(name: string; entry: JsonNode): string {.raises: [].} =
  ## The lock entry's identity — name · version · vcsRevision ·
  ## checksums.sha1 (the pin record R-NT (b) requires).
  var version = ""
  var revision = ""
  var sha1 = ""
  if entry.kind == JObject:
    let v = entry.getOrDefault("version")
    if v.kind == JString:
      version = v.getStr()
    let r = entry.getOrDefault("vcsRevision")
    if r.kind == JString:
      revision = r.getStr()
    let c = entry.getOrDefault("checksums")
    if c.kind == JObject:
      let s = c.getOrDefault("sha1")
      if s.kind == JString:
        sha1 = s.getStr()
  name & "@" & version & "#" & revision & "#" & sha1

# ---------------------------------------------------------------------------
# The derivation
# ---------------------------------------------------------------------------

proc deriveTestedTreeClosure*(repoRoot, treeOid: string;
    entryPaths, fixturePaths: seq[string]): Result[TestedTreeClosure, string] {.
  raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect,
  tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The full derivation — the closure of `entryPaths` over the tested tree,
  ## the fixture set's digest, the pin identity, and every classified
  ## dependency. Fail-closed: a malformed tree OID, an unreadable tree, an
  ## unparsable source, a missing fixture or a missing lock entry is an err.
  ## The working directory is never read.
  if not isHexLen(treeOid, 40):
    return err("tested_tree_closure: tested tree OID is not 40-hex (fail-closed): '" &
      treeOid & "'")
  let universe = listTreeUniverse(repoRoot, treeOid)
  if universe.isErr:
    return err(universe.error)
  var byPath = initTable[string, TreeElement]()
  for e in universe.get:
    byPath[e.path] = e
  if byPath.len == 0:
    return err("tested_tree_closure: the tested tree has an empty universe (fail-closed)")

  # The lock — M's OWN nimble.lock (the pin source; never the workdir's).
  var lockPackages = initTable[string, JsonNode]()
  if byPath.hasKey(NimbleLockPath):
    let lockBlob = readBlob(repoRoot, byPath[NimbleLockPath].oid)
    if lockBlob.isErr:
      return err(lockBlob.error)
    var lockNode: JsonNode
    try:
      lockNode = parseJson(lockBlob.get)
    except CatchableError as e:
      return err("tested_tree_closure: " & NimbleLockPath &
        " is unparsable (fail-closed): " & e.msg)
    if lockNode.kind != JObject:
      return err("tested_tree_closure: " & NimbleLockPath &
        " is not a JSON object (fail-closed)")
    let packages = lockNode.getOrDefault("packages")
    if packages.kind == JObject:
      for name, entry in packages.pairs:
        lockPackages[name] = entry

  var closure = TestedTreeClosure(probeTreeOid: treeOid)
  var visited = initHashSet[string]()
  var bgEvaluated = initHashSet[string]()
  var pinIdentities = initTable[string, string]()
  var pending: seq[string] = @[]
  for e in entryPaths:
    if not byPath.hasKey(e):
      return err("tested_tree_closure: the closure entry is absent from the tested " &
        "tree (fail-closed): " & e)
    if e notin visited:
      visited.incl(e)
      pending.add(e)

  while pending.len > 0:
    # Read this round's blobs in ONE git call.
    var oids: seq[string] = @[]
    for p in pending:
      oids.add(byPath[p].oid)
    let blobs = readBlobs(repoRoot, oids)
    if blobs.isErr:
      return err(blobs.error)
    var nextRound: seq[string] = @[]
    for p in pending:
      let element = byPath[p]
      closure.members.add(element)
      if not blobs.get.hasKey(element.oid):
        return err("tested_tree_closure: the closure member's blob is absent from " &
          "the object store (fail-closed): " & p)
      let source = blobs.get[element.oid]
      let ast = parseStringAST(source)
      if ast.isNil:
        return err("tested_tree_closure: the closure member's source does not " &
          "parse (fail-closed): " & p)
      for token in importTokensOf(ast):
        if token.len == 0:
          continue
        var dep = ClosureDependency(rawImport: token, importer: p)
        let resolved = resolveTreePath(token, p, byPath)
        if resolved.len > 0:
          dep.klass = dcTreeMember
          dep.treePath = resolved
          dep.blobOid = byPath[resolved].oid
          dep.note = "tree member — the blob OID is a closure input"
          if resolved notin visited:
            visited.incl(resolved)
            nextRound.add(resolved)
        else:
          let pin = lockEntryName(token, lockPackages)
          if pin.len > 0:
            dep.klass = dcPinnedExternal
            dep.pinName = pin
            let identity = lockEntryIdentity(pin, lockPackages[pin])
            pinIdentities[pin] = identity
            dep.note = "pinned by " & NimbleLockPath & " entry '" & pin &
              "' — the lock entry identity is a closure input"
            closure.notes.add("b|" & token & "|imported by " & p & " — " & dep.note)
          elif isStdlibToken(token):
            dep.klass = dcStdlib
            dep.note = "stdlib — compiler-shipped, bound by component ⑧ (the compiler pin)"
          else:
            var bg: BuildGeneratedModule
            var isBuildGenerated = false
            for candidate in BuildGeneratedModules:
              if candidate.token == token:
                bg = candidate
                isBuildGenerated = true
                break
            if isBuildGenerated:
              dep.klass = dcBuildGenerated
              dep.note = bg.boundBy
              # The admissibility of a build-generated module is a property
              # of the MODULE, not of its importer — evaluate it once.
              if token notin bgEvaluated:
                bgEvaluated.incl(token)
                # The committed template IS a tree member — its blob binds
                # the tree-bound constants. The template's own exports are
                # compared against the DECLARED symbol set (the drift guard):
                # an exported symbol nobody declared is an unbound value.
                if not byPath.hasKey(bg.templatePath):
                  closure.nonReusable.add("c|" & token & "|the build-generated module's " &
                    "committed template is absent from the tested tree (" &
                    bg.templatePath & ") — the closure is not reusable")
                  dep.note = "the committed template is absent from the tested tree"
                else:
                  let templateBlob = readBlob(repoRoot, byPath[bg.templatePath].oid)
                  if templateBlob.isErr:
                    return err(templateBlob.error)
                  let templateAst = parseStringAST(templateBlob.get)
                  if templateAst.isNil:
                    return err("tested_tree_closure: the build-generated module's " &
                      "template does not parse (fail-closed): " & bg.templatePath)
                  var declared = initHashSet[string]()
                  for sym in bg.symbols:
                    declared.incl(sym)
                  var exported = initHashSet[string]()
                  for sym in exportedConstNames(templateAst):
                    exported.incl(sym)
                  for sym in exported:
                    if sym notin declared:
                      closure.nonReusable.add("c|" & token & "|the build-generated module " &
                        "exports the undeclared symbol '" & sym & "' — the closure is " &
                        "not reusable (the declared symbol set drifted)")
                  # A declared symbol the tree's template does not export is
                  # NOT a drift: the module simply does not contribute it in
                  # this tree (an older tree's template is smaller) — the
                  # symbol is recorded, not refused.
                  var absent: seq[string] = @[]
                  for sym in bg.symbols:
                    if sym notin exported:
                      absent.add(sym)
                  if absent.len > 0:
                    closure.notes.add("c|" & token & "|the module's template in this tree " &
                      "does not export " & $absent.len & " declared symbol(s) (" &
                      absent.join(",") & ") — they contribute no value here")
                  if bg.templatePath notin visited:
                    visited.incl(bg.templatePath)
                    nextRound.add(bg.templatePath)
              closure.notes.add("c|" & token & "|imported by " & p & " — " & dep.note)
            else:
              dep.klass = dcUnresolved
              dep.note = "unresolvable in the tested tree and unpinned in " &
                NimbleLockPath & " — the closure is not reusable"
              closure.notes.add("d|" & token & "|imported by " & p & " — " & dep.note)
              closure.nonReusable.add("d|" & token & "|imported by " & p &
                " — unresolvable and unpinned: the closure is not reusable")
        closure.dependencies.add(dep)
    pending = nextRound

  # The closure's digest (①) — the canonical element-record stream over the
  # resolved members' blob OIDs (the same lossless canonicalization ⑤ uses:
  # the record binds path · mode · type · blob OID, sorted in byte order and
  # NUL-terminated; the CONTENT identity comes from the blob OIDs alone).
  closure.sourceDigest = semanticDigestFromRecords(closure.members)

  # The fixture set's digest (③) — the fixture paths' blob OIDs from M's tree.
  var fixtureElements: seq[TreeElement] = @[]
  for f in fixturePaths:
    if not byPath.hasKey(f):
      return err("tested_tree_closure: the fixture is absent from the tested tree " &
        "(fail-closed): " & f)
    fixtureElements.add(byPath[f])
  closure.fixturesDigest = semanticDigestFromRecords(fixtureElements)

  # The pin identity (narrowing-only) — the lock entries the closure rests
  # on, in a canonical order.
  var pinNames: seq[string] = @[]
  for name in pinIdentities.keys:
    pinNames.add(name)
  pinNames.sort()
  var identity = ""
  for name in pinNames:
    if identity.len > 0:
      identity.add("|")
    identity.add(pinIdentities[name])
  closure.pinIdentity = identity
  ok(closure)

{.pop.}
