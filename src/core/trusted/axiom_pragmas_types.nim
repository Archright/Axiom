# nim-check: skip (include fragment — not an independent translation unit)


when fileExists("src/generated/build_env.nim"):
  import generated/build_env
  const axiomPragmaHasBuildEnv* = true
else:
  # Fallback used only when build_env.nim is absent (fresh checkout + a compile
  # that skipped config.nims, e.g. AXIOM_GATE_BOND / --skipProjCfg gate self-
  # builds). The shipped binary path always materializes build_env.nim first via
  # config.nims, so these placeholders never reach a production binary — they only
  # keep gate/tool compiles (where axiomDebt is never instantiated) resolvable.
  const axiomPragmaHasBuildEnv* = false
  const BuildEnvProjectRoot* = ""
  const BuildEnvBuildDate* = ""

when fileExists("src/generated/import_rules_static.nim"):
  import generated/import_rules_static
else:
  const forbiddenCoreImports* = [
    "infrastructure/", "gate/", "cli/", "verification/", "ui/", "frontend/",
    "personas/", "sieve/", "engine/", "semantic_proofs/", "generated/",
    "mcp/", "api/", "policy/"
  ]

var importGuardCache {.compileTime.}: Table[string, bool]

var stageRegistry* {.compileTime.}: seq[(string, string)]

type
  AxiomEntryOrigin* = enum
    soAxiomSupport
    soExternalSubject

var externalSubjectMode* {.threadvar.}: bool

template setExternalSubjectMode*(v: bool) =
  ## Template (not proc): respects the src/core proc-declaration budget cap.
  externalSubjectMode = v

type
  AxiomCompileEntry* = object
    funcName*: string
    irSerialized*: string
    irHash*: string
    smtSource*: string
    leanSource*: string
    sourcePath*: string
    isKernel*: bool
    effectKind*: AxiomEffectKind
    bmcSkippable*: bool

var axiomRegistry* {.compileTime.}: seq[AxiomCompileEntry]

type
  RuntimeAxiomEntry* = object
    name*: string
    irSerialized*: string
    smtSource*: string
    leanSource*: string
    sourcePath*: string
    isKernel*: bool
    irHash*: string
    effectKind*: AxiomEffectKind
    bmcSkippable*: bool
    origin*: AxiomEntryOrigin = soAxiomSupport
    expectedObligation*: bool  ## Explicit scope contract: does this proof-mode symbol
                               ## REQUIRE at least one semantic/safety obligation?
                               ## Default false — cnaNoObligations is NOT auto-promoted to
                               ## ScopeInconsistency unless this is declared true (anti-theater:
                               ## a CHC result alone must not overwrite scope policy).
    sourceContent*: string = ""  ## Resolver-authorised source bytes this entry was
                               ## materialised from.  Populated ONLY by
                               ## materializeExternalIR, which retains what its
                               ## ModuleContentResolver already returned (WP4-a
                               ## B-5b: the resolver owns source location; that module
                               ## performs no disk I/O).  `sourcePath` for such an entry
                               ## is subject-relative and is NOT resolvable against the
                               ## process CWD.  Empty means "not carried" — consumers
                               ## must fall back to path-relative resolution or fail
                               ## closed; it never authorises a path-derived hash.

var runtimeAxiomRegistry*: seq[RuntimeAxiomEntry] = @[]

type
  PropertyKind* = enum
    pkCommutative
    pkAssociative
    pkIdempotent
    pkIdentity
    pkInverse
    pkDistributive
    pkMonotonic
    pkConfluent

var registryLookup*: Table[string, RuntimeAxiomEntry]

type
  ModuleContentResolver* = proc(modulePath: string): Option[string] {.raises: [], axiomEffect: IOEffect.}
    ## Resolve module source content by relative module path.
    ##
    ## The resolver OWNS source-location resolution.  A caller may bind it to
    ## a subjectRoot so it resolves modulePath against that root (including
    ## disk reads), rather than against process CWD.  The pragma is
    ## `axiomEffect: IOEffect` (not `noSideEffect`) because a disk-backed
    ## resolver performs read I/O; `raises: []` is retained so a resolver
    ## never surfaces an exception (disk reads wrap failures into `none`).
    ##
    ## WP4-a B-5b: source fallback based on getCurrentDir() is removed —
    ## the resolver decides location, never the caller's CWD.

const domainContractMap*: array[8, tuple[prefix, contract: string]] = [
  (prefix: "topology",     contract: "topology_contract"),
  (prefix: "orchestrator", contract: "orchestrator_contract"),
  (prefix: "proof",        contract: "proof_contract"),
  (prefix: "audit",        contract: "audit_contract"),
  (prefix: "solver",       contract: "solver_contract"),
  (prefix: "vault",        contract: "vault_contract"),
  (prefix: "cache",        contract: "cache_contract"),
  (prefix: "logging",      contract: "logging_contract"),
]
