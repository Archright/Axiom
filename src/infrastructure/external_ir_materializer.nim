import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

# experiment-only: not canonical execution path, not production API

## External IR Materializer — produce IR entries for symbols that live
## outside the Axiom kernel (subject under test) but are not registered
## in the runtime axiom registry.  This module is used exclusively by the
## external proof candidate pipeline (WP4-a) and is not part of the
## canonical execution path.

import std/options
import std/strutils
import std/tables
import std/sequtils
import core/parser_utils
import compiler/[ast, idents]
import core/trusted/pnode_to_canon
import core/trusted/ast_to_ir
import core/trusted/axiom_ir
import core/trusted/axiom_pragmas
import core/trusted/binding_inventory
import core/trusted/semantic_fact_types
import core/trusted/completeness_binding
import core/crypto/hash_kernel
import infrastructure/evidence_artifact_io
import core/deterministic_cas_key
import verification/obligation/canonical_verification
import verification/obligation/lean_kernel_boundary
import verification/obligation/toolchain_capture

# ---------------------------------------------------------------------------
# SubjectSymbolRef — minimal lookup identity
# ---------------------------------------------------------------------------

type
  SubjectSymbolRef* = object
    relativeModulePath*: string  ## Path to the source file (relative to project root)
    functionName*: string        ## Name of the function/proc to materialize
  ## MINIMAL lookup identity — NOT guaranteed unique.  When the same
  ## function name appears in multiple overloads within the same module,
  ## the result is moAmbiguousOverload (fail-closed; first-match is
  ## explicitly NOT adopted as product semantics).

  MaterializationOutcome* = enum
    moMaterialized     ## Successfully produced a synthesized entry
    moNotFound         ## No matching function definition found in source
    moAmbiguousOverload ## Multiple definitions with the same name found
    moParseFailure     ## Source could not be read or parsed
    moUnsupportedDeclKind ## The declaration WAS found, but its kind has no
                           ## IR translation.  Deliberately distinct from
                           ## moNotFound: a subject symbol that exists must
                           ## never be reported as absent.
                           ## `ExternalIrEntry.unsupportedReason` carries the
                           ## explanation.

  ExternalIrEntry* = object
    entry*: RuntimeAxiomEntry
    funcDef*: IRFuncDef
    unsupportedReason*: string ## Populated only on moUnsupportedDeclKind;
                               ## empty on every other outcome.
    parseBound*: SubjectParseBoundComponents = SubjectParseBoundComponents()
      ## §2.1a parse-bound components carried with the entry. A synthesized
      ## relational composite is populated at its synthesis site (main
      ## thread) with the two ORIGINAL symbols' EA legs; the selection
      ## boundary re-measures only entries that arrive empty.

# ---------------------------------------------------------------------------
# Declaration-kind taxonomy
#
# SSOT is `ProcDefKinds` in src/core/parsers/pnode_nav.nim.  It is INLINED
# here rather than imported: `core/parsers/` is an encapsulated InternalPath
# (src/gate/gate_consts.nim) and the `src/infrastructure/` exemption list
# covers only core/contracts/, core/topology/ and core/trusted/ — so importing
# it would be an import-encapsulation violation.
#
# SYNC POINT (nimtry manifest slice S2, V4 registry inversion): the per-kind
# name extraction and the per-tag spec application are dispatch REGISTRIES
# (`headNameExtractors` / `specTagHandlers`, populated via `register` at
# module init) — a new head shape or spec tag is added by registering a
# handler, not by editing the traversal/extraction logic.  Keep the two
# taxonomies in sync through these registries.
# ---------------------------------------------------------------------------

const
  DiscoverableDefKinds*: set[TNodeKind] =
    {nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef,
     nkConverterDef, nkMacroDef, nkTemplateDef}
    ## Declaration kinds this module can SEE in the subject.

  IrTranslatableDefKinds*: set[TNodeKind] = {nkProcDef, nkFuncDef}
    ## Subset of `DiscoverableDefKinds` that `pnodeToCanon` / `axiomBodyCanon`
    ## can translate.  The remaining kinds are discovered and reported as
    ## moUnsupportedDeclKind — never dropped, never treated as absent.

  DefKindOrder: array[7, TNodeKind] =
    [nkProcDef, nkFuncDef, nkMethodDef, nkIteratorDef,
     nkConverterDef, nkMacroDef, nkTemplateDef]
    ## Canonical ordering of `DiscoverableDefKinds`, so the reason string does
    ## not depend on AST traversal order.

# ---------------------------------------------------------------------------
# Explicit axiom-spec payload (PNode side)
#
# The `{.axiom: [pre: (…), post: (…), smt: "…", lean: "…"].}` pragma is the
# product's declared explicit-spec channel. The kernel lane ingests it at
# compile time (axiom_pragmas_macros.extractAxiomSpec/applyAxiomSpec); the
# external lane reads the same pragma off the raw PNode here. Unknown pragmas
# are inert at parse time, so a subject that never imports core/axiom_pragmas
# still carries the spec as syntax.
# ---------------------------------------------------------------------------

type
  ExternalAxiomSpec* = object
    ## Raw explicit-spec payload extracted from a routine's `axiom` pragma.
    pre*, post*: seq[PNode]  ## Spec expression PNodes, paren-unwrapped
    smt*, lean*: string      ## Verifier hint strings, when present
    present*: bool           ## An `axiom: […]` pragma list was found

func unwrapParenP(n: PNode): PNode =
  result = n
  while not result.isNil and result.kind in {nkPar, nkStmtListExpr} and result.len == 1:
    result = result[0]

# ---------------------------------------------------------------------------
# Dispatch registries (OCP inversion — nimtry manifest slice S2, V4)
#
# Per-kind name extraction and per-tag spec application are registry
# strategies instead of hard-coded `case` chains: a new declaration-head
# shape or a new axiom-spec tag extends this module by `register`ing a
# handler (see the taxonomy SYNC POINT above).  Both tables are populated
# once at module init and are read-only afterwards; registry iteration order
# is never relied upon (the unsupported-kind reason string is emitted in
# `DefKindOrder`, never in registry order).
# ---------------------------------------------------------------------------

type
  DefHeadNameExtract* = proc(head: PNode): string {.noSideEffect, raises: [].}
    ## Extracts the declared name text from a routine-definition head node.
    ## (`func` type syntax is rejected by the compiler in type descriptions —
    ## `proc` + `{.noSideEffect.}` is its exact spelling.)
  AxiomSpecTagApply* = proc(argValue: PNode; spec: var ExternalAxiomSpec) {.
      noSideEffect, raises: [].}
    ## Applies one `axiom: [tag: value]` bracket entry to the accumulating
    ## spec.

var headNameExtractors = initTable[TNodeKind, DefHeadNameExtract]()
  ## Definition-head node kind → name extractor (read-only after module init).

var specTagHandlers = initTable[string, AxiomSpecTagApply]()
  ## Axiom-spec bracket tag → value applier (read-only after module init).

template register*(kind: TNodeKind; extractor: DefHeadNameExtract) =
  ## Bind the name extractor for one definition-head node kind into the
  ## dispatch registry.  OCP seam (nimtry manifest slice S2, V4): a new head
  ## shape extends this module by one registration, not by editing the
  ## traversal logic.  A template, not a proc: registration is an init-time
  ## imperative bind of the module's composition root, not a runtime function.
  headNameExtractors[kind] = extractor

template register*(tag: string; apply: AxiomSpecTagApply) =
  ## Bind the value applier for one axiom-spec bracket tag into the dispatch
  ## registry.  OCP seam; same template rationale as the kind overload.
  specTagHandlers[tag] = apply

func extractIdentHeadName(head: PNode): string {.raises: [].} =
  head.ident.s

func extractSymHeadName(head: PNode): string {.raises: [].} =
  head.sym.name.s

func extractPostfixHeadName(head: PNode): string {.raises: [].} =
  ## `name*` postfix form: the declared identifier is child 1; any other
  ## shape yields "" (no name → no match), exactly like the former `else`.
  if head.len > 1 and not head[1].isNil and head[1].kind == nkIdent:
    head[1].ident.s
  else: ""

func applySmtTag(argValue: PNode; spec: var ExternalAxiomSpec) {.raises: [].} =
  if not argValue.isNil and argValue.kind == nkStrLit:
    spec.smt = argValue.strVal

func applyLeanTag(argValue: PNode; spec: var ExternalAxiomSpec) {.raises: [].} =
  if not argValue.isNil and argValue.kind == nkStrLit:
    spec.lean = argValue.strVal

func applyPreTag(argValue: PNode; spec: var ExternalAxiomSpec) {.raises: [].} =
  if not argValue.isNil:
    spec.pre.add(unwrapParenP(argValue))

func applyPostTag(argValue: PNode; spec: var ExternalAxiomSpec) {.raises: [].} =
  if not argValue.isNil:
    spec.post.add(unwrapParenP(argValue))

register(nkIdent, extractIdentHeadName)
register(nkSym, extractSymHeadName)
register(nkPostfix, extractPostfixHeadName)
register("smt", applySmtTag)
register("lean", applyLeanTag)
register("pre", applyPreTag)
register("post", applyPostTag)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func declKindReason*(matches: seq[PNode]): string =
  ## Render the fail-closed reason for declarations that are visible but not
  ## IR-translatable.  Empty string when every match is IR-translatable.
  ## Pure and deterministic: kinds are emitted in `DefKindOrder`, never in
  ## traversal order.
  var listed: seq[string] = @[]
  for k in DefKindOrder:
    if k in IrTranslatableDefKinds: continue
    if matches.anyIt(it.kind == k):
      listed.add($k)
  if listed.len == 0: return ""
  "declaration kind(s) " & listed.join(",") &
    " have no IR translation; this module translates only " &
    $IrTranslatableDefKinds

func findAllFuncDefsP*(root: PNode; procName: string;
    extractors: Table[TNodeKind, DefHeadNameExtract]): seq[PNode] =
  ## Collect all declarations matching `procName` via explicit-stack traversal.
  ## Discovery spans every kind in `DiscoverableDefKinds` — templates, macros,
  ## iterators, converters and methods ARE returned.  Whether the caller can
  ## translate them is a separate question answered by
  ## `IrTranslatableDefKinds`; narrowing discovery would turn "exists but
  ## unsupported" into a silent moNotFound.  Returns an empty seq when no
  ## match is found.  The head-name registry is an explicit parameter: the
  ## caller (the I/O shell) injects the module's composition root, because a
  ## pure func cannot read module globals under strict effect checking.
  var stack: seq[PNode] = @[root]
  while stack.len > 0:
    let n = stack.pop()
    if n.isNil: continue
    if n.kind in {nkEmpty, nkIdent, nkSym, nkCharLit,
                  nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
                  nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit,
                  nkTripleStrLit, nkNilLit}:
      continue
    if n.kind in DiscoverableDefKinds and n.len > 0:
      var nameText = ""
      let head = n[0]
      if not head.isNil:
        let extract = extractors.getOrDefault(head.kind)
        if not extract.isNil:
          nameText = extract(head)
      if nameText == procName:
        result.add(n)
    for i in 0 ..< n.len:
      if not n[i].isNil and n.kind notin {nkEmpty, nkIdent, nkSym, nkCharLit,
          nkIntLit..nkInt64Lit, nkUIntLit..nkUInt64Lit,
          nkFloatLit..nkFloat128Lit, nkStrLit, nkRStrLit, nkTripleStrLit, nkNilLit}:
        stack.add(n[i])

# ---------------------------------------------------------------------------
# Explicit axiom-spec extraction (PNode side) — registry dispatch
# ---------------------------------------------------------------------------

func extractAxiomSpecP*(def: PNode;
    handlers: Table[string, AxiomSpecTagApply]): ExternalAxiomSpec {.raises: [].} =
  ## PNode mirror of axiom_pragmas_macros.extractAxiomSpec: scan the routine's
  ## pragma child (index 4, same slot the macro-side `node.pragma` accessor
  ## reads) for `axiom: [pre: …, post: …, smt: …, lean: …]`. Non-`axiom`
  ## pragmas and non-bracket payloads are ignored — extraction never fails,
  ## it just finds nothing.  Bracket tags dispatch through the `handlers`
  ## registry (injected by the caller; see `findAllFuncDefsP`) instead of a
  ## hard-coded `case`; an unregistered tag is inert, exactly like the former
  ## `else` branch.
  if def.isNil or def.kind notin DiscoverableDefKinds or def.len < 5:
    return
  let pragma = def[4]
  if pragma.isNil or pragma.kind != nkPragma:
    return
  for child in pragma:
    if child.isNil or child.kind != nkExprColonExpr or child.len < 2:
      continue
    let tag = child[0]
    if tag.isNil or tag.kind != nkIdent or tag.ident.s != "axiom":
      continue
    let args = child[1]
    if args.isNil or args.kind != nkBracket:
      continue
    result.present = true
    for arg in args:
      if arg.isNil or arg.kind notin {nkExprColonExpr, nkCall} or arg.len < 2:
        continue
      let nameNode = arg[0]
      let name = if not nameNode.isNil and nameNode.kind == nkIdent:
                   nameNode.ident.s
                 else: ""
      let apply = handlers.getOrDefault(name)
      if not apply.isNil:
        apply(arg[1], result)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func irBindingNames*(funcDef: IRFuncDef): seq[string] {.raises: [].} =
  ## Every name the translated IR binds — let-bindings, parameters and loop
  ## variables — as one flat list, so the translated and observed binding
  ## universes are compared as multisets rather than per source category.
  ## Exported for the kernel completeness measurement (Phase 1A): the runner's
  ## `measuredKernelCompletenessEvidence` compares THIS list against the
  ## independently observed source inventory through `correspondenceHolds`.
  result = collectLetNames(funcDef.body)
  for param in funcDef.params:
    result.add param.name
  for name in collectLoopVarNames(funcDef):
    result.add name

func bindingMultiset(names: seq[string]): Table[string, int] {.raises: [].} =
  ## Occurrence count per name. Repetition is counted, not deduplicated: a name
  ## bound twice in one scope and once in the other is a real disagreement.
  for name in names:
    result[name] = result.getOrDefault(name) + 1

func correspondenceHolds*(irNames: seq[string]; inventory: BindingInventory): bool {.
    raises: [].} =
  ## True iff the IR's binding-name multiset and the inventory's non-opaque
  ## witness-name multiset agree in both directions. A name carried on only one
  ## side means the translation and the raw AST disagree about the binding
  ## universe, which is fail-closed evidence that the translation is incomplete.
  ## Exported for the kernel completeness measurement (Phase 1A) — the kernel
  ## path reuses the SAME comparison, never a re-implemented one.
  let irCount = bindingMultiset(irNames)
  let invCount = bindingMultiset(inventory.witnesses.filterIt(
    not it.opaque and it.name.len > 0).mapIt(it.name))
  for name, cnt in invCount.pairs:
    if irCount.getOrDefault(name) != cnt:
      return false
  for name, cnt in irCount.pairs:
    if invCount.getOrDefault(name) != cnt:
      return false
  true

# ---------------------------------------------------------------------------
# Phase 1A — strict CompletenessBinding producer capture + kernel inventory
# ---------------------------------------------------------------------------

type CompletenessCaptureIdentity* = object
  ## The measured identity inputs a strict CompletenessBinding producer
  ## records at capture time. `sourceIdentity` "" (or `moduleSha256` "") marks
  ## an UNMEASURABLE capture — the dual-write refuses it, never fabricates a
  ## downgraded identity.
  sourceIdentity*: string   ## composeCompletenessSourceIdentity over git ref
                            ## + tree merkle + module sha ("" = unmeasurable)
  moduleSha256*: string     ## raw sha256 of the subject module bytes

proc measureCompletenessSourceCapture*(subjectRepoRoot, moduleRelPath,
    moduleSource: string; contentCarried: bool = true): CompletenessCaptureIdentity {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Producer-side capture of the strict binding identity inputs. The
  ## subject root is resolved under the SAME rule the strict-first reader
  ## applies (`resolveSubjectRepoRoot` with the caller's contentCarried
  ## flag: a content-carried subject binds ONLY to a threaded root — never
  ## the process CWD; a path-resolved subject falls back to the CWD git
  ## root), so a producer capture and the reader recomputation agree
  ## whenever they observe the same subject tree. Unmeasurable components
  ## (no threaded root, no git identity, unreadable import closure) leave
  ## `sourceIdentity` "" — the dual-write refuses, and the producer
  ## degrades to the legacy-only generation instead of a forged identity.
  let moduleSha = if moduleSource.len > 0: sha256Hex(moduleSource) else: ""
  if moduleSha.len == 0:
    return CompletenessCaptureIdentity()
  let root = resolveSubjectRepoRoot(subjectRepoRoot, moduleRelPath, contentCarried)
  if root.len == 0:
    return CompletenessCaptureIdentity(moduleSha256: moduleSha)
  let gitRef = measureSubjectGitRef(root)
  let treeMerkle = measureSubjectTreeMerkleRoot(root, moduleRelPath, moduleSource)
  if gitRef.len == 0 or treeMerkle.len == 0:
    return CompletenessCaptureIdentity(moduleSha256: moduleSha)
  CompletenessCaptureIdentity(
    sourceIdentity: composeCompletenessSourceIdentity(gitRef, treeMerkle, moduleSha),
    moduleSha256: moduleSha)

proc saveCompletenessEvidenceDual*(evidenceKey: string; funcDef: IRFuncDef;
    capture: CompletenessCaptureIdentity; payload: CompletenessEvidence): bool {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## The single dual-write entry point every strict-generation producer uses:
  ## the caller keeps its legacy `saveEvidenceArtifact(key, payload)` write
  ## untouched, and this persists the authenticated strict sibling —
  ## `irDigest` = the SAME flavor-③ anchor the legacy artifact is keyed by,
  ## `irDigestCanonical` = flavor-② `computeIrDigest(funcDef)` of the funcDef
  ## the payload describes, source identity / module sha from the measured
  ## capture, toolchain fingerprint from the shared bundle measurement
  ## (`measureCanonicalCaptureToolchainFingerprint` — the receipt/CLE
  ## composition, never a forked formula), `semanticProfileId` =
  ## SemanticProfileV1Hash. False on any unmeasured component (fail-closed —
  ## an identity-less binding is never persisted).
  ##
  ## The generation tag is written FIRST: even when measurement fails, the
  ## reader must not silently fall back to the legacy artifact for this anchor
  ## (a new-generation record that cannot produce a strict binding is
  ## UNKNOWN, never legacy-admitted).
  discard markStrictGeneration(evidenceKey)
  if capture.sourceIdentity.len == 0 or capture.moduleSha256.len == 0:
    return false
  saveStrictCompletenessBinding(evidenceKey, computeIrDigest(funcDef),
    capture.sourceIdentity, capture.moduleSha256,
    measureCanonicalCaptureToolchainFingerprint(), payload)

proc measureSourceBindingInventory*(moduleSource, funcName,
    modulePath: string): Option[BindingInventory] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Independent source-side binding observation for the KERNEL completeness
  ## measurement (Phase 1A): parse the module and observe `funcName`'s
  ## definition with the SAME trusted observer and template-instantiation
  ## walk the external materializer uses (binding_inventory.nim lock 21 —
  ## never the translator's traversal). `none` = unmeasurable (empty source,
  ## nil parse, absent or ambiguous definition) — the caller fails
  ## `bindingUniverseComplete` closed, never fabricates a correspondence.
  ## NOT gcsafe (parseStringAST holds process globals): main-thread callers
  ## only — the selection boundary, like measureParseBoundComponents.
  if moduleSource.len == 0 or funcName.len == 0:
    return none(BindingInventory)
  let ast = parseStringAST(moduleSource)
  if ast.isNil:
    return none(BindingInventory)
  let matches = findAllFuncDefsP(ast, funcName, headNameExtractors)
  if matches.len != 1:
    return none(BindingInventory)
  var inv = inventoryFromPNode(matches[0], funcName)
  observeInstantiations(ast, modulePath, inv)
  some(inv)

proc synthesizeExternalEntry*(symRef: SubjectSymbolRef; funcDef: IRFuncDef;
                              sourceContent: string = ""): RuntimeAxiomEntry =
  ## Produce a RuntimeAxiomEntry for an external subject symbol.
  ##
  ## Field annotations:
  ## - registry fact: name, sourcePath, origin = soExternalSubject
  ## - IR-derived fact: bmcSkippable = isBmcSkippable(funcDef)
  ## - policy assertion: effectKind = Pure — NOT a semantic fact.  The
  ##   external proof pipeline only handles pure candidates, so this is
  ##   a conservative policy value until effect analysis lands.
  ## - isKernel = false — asserts no kernel-scope membership; passing
  ##   path is the origin branch.
  ## - sourceContent: bytes the caller already holds.  This proc adds no
  ##   I/O of its own; an empty value means "caller carried nothing".
  result.name = symRef.functionName
  result.irSerialized = serializeIRFuncDef(funcDef)
  result.smtSource = ""
  result.leanSource = ""
  result.sourcePath = symRef.relativeModulePath
  result.isKernel = false
  result.irHash = ""
  result.effectKind = Pure
  result.bmcSkippable = isBmcSkippable(funcDef)
  result.origin = soExternalSubject
  result.expectedObligation = false
  result.sourceContent = sourceContent

type
  MaterializationCore = object
    ## Pure pipeline result — everything the I/O shell needs in order to
    ## persist artifacts and return.  `evidence`, `irDigest` and `witnesses`
    ## are meaningful only on `moMaterialized`; `entry` carries the
    ## `unsupportedReason` on `moUnsupportedDeclKind` and is otherwise the
    ## default value on non-materialized outcomes.
    outcome: MaterializationOutcome
    entry: ExternalIrEntry
    evidence: CompletenessEvidence
    irDigest: string
    witnesses: seq[InstantiationWitness]

func ingestExplicitSpec(irFuncDef: var IRFuncDef; spec: ExternalAxiomSpec): bool {.raises: [].} =
  ## Convert the declared pre/post expressions through the same
  ## CanonNode→IRExpr translator as the body.  Returns the translator's lossy
  ## verdict: true means the spec has no IR translation — the caller must
  ## fail closed (existing-but-untranslatable), never continue with a
  ## silently spec-less candidate (a dropped spec would verify the body
  ## against an invented contract instead of the declared one).
  var specCtx = initIrContext(irFuncDef.name, irFuncDef.params)
  for p in spec.pre:
    irFuncDef.preConditions.add(convertExprCanon(pnodeToCanon(p), specCtx))
  for p in spec.post:
    irFuncDef.postConditions.add(convertExprCanon(pnodeToCanon(p), specCtx))
  specCtx.lossySeen

func materializeExternalIRCore(symRef: SubjectSymbolRef; ast: PNode; source: string;
    extractors: Table[TNodeKind, DefHeadNameExtract];
    handlers: Table[string, AxiomSpecTagApply]): MaterializationCore {.raises: [].} =
  ## Pure translation pipeline — the computation half of the materialization
  ## split (nimtry manifest slice S2, V3): discover → fail-closed unsupported
  ## check → ambiguity → canonical IR → axiom-spec ingestion →
  ## binding-inventory observation → completeness evidence → CAS digest →
  ## synthesized entry.  Operates on the caller-parsed AST (`ast`) plus the
  ## resolver's verbatim bytes (`source`, carried onto the entry) — parsing
  ## itself belongs to the I/O shell because `parseStringAST` performs
  ## best-effort diagnostic I/O on parse failure.  NO resolver call, NO
  ## artifact persistence, NO I/O of any kind, and the dispatch registries
  ## are injected parameters — the shell owns acquisition, parsing and
  ## persistence ordering.
  ##
  ## Frozen contracts (unchanged from the pre-split pipeline):
  ## - Any discovered declaration whose kind is outside
  ##   `IrTranslatableDefKinds` → `moUnsupportedDeclKind` with
  ##   `entry.unsupportedReason` naming the kinds, checked BEFORE the
  ##   ambiguity check (fail-closed visibility: an existing symbol is never
  ##   reported as absent).  No expansion or semantic handling is performed
  ##   for those kinds.
  ## - Multiple definitions of the same name → `moAmbiguousOverload`
  ##   (fail-closed; first-match is NOT adopted as product semantics).
  ## - A nil parse result → `moParseFailure`; an empty IR name →
  ##   `moParseFailure`.
  ## - A spec expression the translator cannot represent (lossy) →
  ##   existing-but-untranslatable, never a silently spec-less candidate (a
  ##   dropped spec would verify the body against an invented contract
  ##   instead of the declared one).
  ## - The artifact key contract (WP4-j.4) is honored by the shell using
  ##   `irDigest` = `computeDeterministicCasKey(serializeIRFuncDef(...))`,
  ##   so replay finds the evidence artifact.
  # --- find matching declarations ---
  let matches = findAllFuncDefsP(ast, symRef.functionName, extractors)
  if matches.len == 0:
    result.outcome = moNotFound
    return

  # Fail-closed on visible-but-untranslatable declarations, BEFORE the
  # ambiguity check: when a name denotes both a translatable and an
  # untranslatable declaration, picking either would be the first-match
  # heuristic this module refuses elsewhere.  Naming such a symbol
  # moNotFound is the silent omission this gate exists to prevent.
  let unsupportedReason = declKindReason(matches)
  if unsupportedReason.len > 0:
    result.outcome = moUnsupportedDeclKind
    result.entry = ExternalIrEntry(unsupportedReason: unsupportedReason)
    return

  if matches.len > 1:
    result.outcome = moAmbiguousOverload
    return

  # --- canonical IR production ---
  let funcDefNode = matches[0]
  let canonNode = pnodeToCanon(funcDefNode)
  var irFuncDef = axiomBodyCanon(canonNode)
  if irFuncDef.name.len == 0:
    result.outcome = moParseFailure
    return

  # --- explicit axiom-spec ingestion (pragma channel) ---
  let spec = extractAxiomSpecP(funcDefNode, handlers)
  if spec.pre.len > 0 or spec.post.len > 0:
    if ingestExplicitSpec(irFuncDef, spec):
      result.outcome = moUnsupportedDeclKind
      result.entry = ExternalIrEntry(unsupportedReason:
        "axiom spec expression has no IR translation (translator marked loss); the explicit spec cannot be ingested for this symbol")
      return

  # ── Independent binding inventory observation (lock 21) ──
  # Raw PNode observer — independent of the translator.
  # observeInstantiations scans the whole module AST for template
  # bodies (not the funcDefNode subtree, since the template is a
  # module-level sibling of the generic func).
  var inventory = inventoryFromPNode(funcDefNode, irFuncDef.name)
  observeInstantiations(ast, symRef.relativeModulePath, inventory)

  # IR binding-name multiset (collectLetNames + params + loopVars).
  let irLetNames = irBindingNames(irFuncDef)

  # Correspondence: IR name multiset ↔ inventory name multiset.
  let correspondenceOk = correspondenceHolds(irLetNames, inventory)

  # Completeness evidence — independent-source observation.
  let lossFree = irFuncDef.translationLossFree
  let hasOpaque = inventory.opaqueBoundaries.len > 0
  let bindingComplete = lossFree and correspondenceOk and (not hasOpaque)
  irFuncDef.bindingUniverseComplete = bindingComplete
  let evidence = CompletenessEvidence(
    translationLossFree: lossFree,
    bindingUniverseComplete: bindingComplete,
    opaqueExpansionStatus: (if hasOpaque: "opaque-boundary-present" else: "none"),
    sourceBindingCount: inventory.witnesses.filterIt(not it.opaque).len,
    irBindingCount: irLetNames.len)

  # WP4-j.4: artifact key MUST match the runner cache scheme —
  # computeDeterministicCasKey(serializeIRFuncDef(...)) — so replay finds it.
  # (The save itself belongs to the I/O shell; the KEY is pipeline data.)
  let irDigest = computeDeterministicCasKey(serializeIRFuncDef(irFuncDef))

  # `source` is the resolver's own return value — carried verbatim so the
  # verification layer can digest §6a input identity without any re-read.
  # An explicitly declared spec raises the scope contract: proof_integrity
  # treats expectedObligation=true with zero derived obligations as a scope
  # mismatch (fail), not a legitimate no-op.
  var entry = synthesizeExternalEntry(symRef, irFuncDef, source)
  entry.expectedObligation = spec.pre.len > 0 or spec.post.len > 0

  result.outcome = moMaterialized
  result.entry = ExternalIrEntry(entry: entry, funcDef: irFuncDef)
  result.evidence = evidence
  result.irDigest = irDigest
  result.witnesses = inventory.instantiationWitnesses

proc materializeExternalIR*(symRef: SubjectSymbolRef; resolver: ModuleContentResolver;
                            subjectRepoRoot: string = ""): tuple[outcome: MaterializationOutcome, entry: ExternalIrEntry] =
  ## I/O shell around the pure `materializeExternalIRCore` pipeline
  ## (nimtry manifest slice S2, V3): acquire source content through the
  ## resolver, run the pure pipeline, then persist the completeness-evidence
  ## artifact and any instantiation witnesses BEFORE returning
  ## `moMaterialized`.
  ##
  ## `subjectRepoRoot` (Phase 1A): the subject root the caller threaded from
  ## the pipeline — the SAME root the strict-first reader resolves, so the
  ## strict binding's sourceIdentity recomputes to the recorded value. Empty
  ## means no threaded root: the strict dual-write capture is then
  ## unmeasurable (content-carried subjects never fall back to the process
  ## CWD) and only the legacy artifact is written.
  ##
  ## Shell-owned frozen contracts:
  ## - The resolver OWNS source-location resolution (it is bound to the
  ##   subject root by the caller) and never consults process CWD.  A `none`
  ##   result is a hard `moParseFailure` — this module performs NO disk I/O
  ##   for source acquisition and has NO getCurrentDir()-based fallback
  ##   (WP4-a B-5b).  Source location is decided entirely by the resolver,
  ##   never by this module or by CWD.
  ## - Persistence ORDER is contractual (WP4-j.4): the artifact key is the
  ##   runner-cache digest (`core.irDigest`) and the evidence artifact is
  ##   saved BEFORE the `moMaterialized` result is returned, so replay
  ##   finds it.
  ## - The `source` bytes flow into `entry.entry.sourceContent` via the
  ##   core, so downstream §6a input identity can be a content hash without
  ##   re-opening `sourcePath`.
  try:
    # --- source content resolution + parse (resolver owns location, not CWD) ---
    let sourceContent = resolver(symRef.relativeModulePath)
    if sourceContent.isNone:
      # Resolver authority resolved the location and found no content.
      # No CWD-based readFile fallback exists here.
      return (outcome: moParseFailure, entry: default(ExternalIrEntry))
    let source = sourceContent.get()
    let ast = parseStringAST(source)
    if ast.isNil:
      return (outcome: moParseFailure, entry: default(ExternalIrEntry))

    # Parsing is shell-owned (parseStringAST performs best-effort diagnostic
    # I/O on failure); the registries are injected from the module's
    # composition root so the pure core never touches module globals.
    let core = materializeExternalIRCore(symRef, ast, source,
      headNameExtractors, specTagHandlers)

    # --- artifact persistence (I/O half of the split) ---
    if core.outcome == moMaterialized:
      saveEvidenceArtifact(core.irDigest, core.evidence)
      # Phase 1A dual-write: the authenticated strict sibling at the SAME
      # anchor. Fail-closed on any unmeasured capture component — the legacy
      # artifact above still lands, and the strict-first reader accepts it
      # only while AXIOM_EVIDENCE_STRICT is unset.
      let capture = measureCompletenessSourceCapture(subjectRepoRoot,
        symRef.relativeModulePath, source)
      discard saveCompletenessEvidenceDual(core.irDigest, core.entry.funcDef,
        capture, core.evidence)
      if core.witnesses.len > 0:
        saveInstantiationWitnesses(core.irDigest, symRef.relativeModulePath,
          "axiom-witness-collector", "v1", "witness-v1", core.witnesses)

    return (outcome: core.outcome, entry: core.entry)
  except CatchableError:
    return (outcome: moParseFailure, entry: default(ExternalIrEntry))

{.pop.}
