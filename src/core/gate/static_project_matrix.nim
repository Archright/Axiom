import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Static Project Matrix — BSS-anchored singleton for zero-heap pipeline context.
##
## PipelineContext holds the entire project state in fixed-size arrays.
## Placed in .bss segment via {.global.} — zero heap allocation.
## =copy and =sink are forbidden (compile-time error) to prevent accidental copying.
##
## v26: PageSize is a compile-time literal via {.intdefine.} — no runtime sysconf.

import core/crypto/hash_kernel

const
  AxiomFileCount* = 792
    ## Number of .nim source files in the project.
  MaxImportsPerFile* = 32
    ## Maximum imports tracked per file for dependency analysis.
  AxiomLedgerCap* = 57
    ## Ledger slot capacity (upper bound ≥ live gate count 57).

type
  StaticFileEntry* = object
    ## Per-file metadata — fixed size, no heap.
    pathHash*: uint32       ## FNV-1a of relative path
    contentHash*: HashValue ## SHA-256 of file content
    size*: int64            ## File size in bytes
    exists*: bool           ## Whether file exists on disk
    osError*: int16         ## OS error code (0 = success)

  StaticASTEntry* = object
    ## Per-file AST metadata — fixed size, no heap.
    procCount*: int32
    funcCount*: int32
    importCount*: int32
    importHashes*: array[MaxImportsPerFile, uint32]

  PipelineContext* = object
    ## The entire project state in a single BSS object.
    ## ~151KB total: 792 × (56 + 140) bytes.
    matrix*: array[AxiomFileCount, StaticFileEntry]
    astCache*: array[AxiomFileCount, StaticASTEntry]
    sourceHash*: HashValue       ## Merkle root of all source files
    combinedStateHash*: HashValue ## Hash of entire pipeline state
    hasVoidArtifact*: bool       ## Whether any void artifact was detected
    manifestData*: pointer       ## manifest_provider 데이터 핸들

# ─── Copy/Sink Guards ────────────────────────────────────────────────────────
# Prevent accidental copying of the 155KB BSS object.

proc `=copy`*(dest: var PipelineContext; src: PipelineContext) {.error: "BSS Matrix 복사 금지 — ptr PipelineContext 사용".}
proc `=sink`*(dest: var PipelineContext; src: PipelineContext) {.error: "BSS Matrix 이동 금지 — ptr PipelineContext 사용".}

# ─── Compile-Time Layout Verification ────────────────────────────────────────

static:
  assert sizeof(StaticFileEntry) == 56,
    "StaticFileEntry size mismatch: expected 56, got " & $sizeof(StaticFileEntry)
  assert sizeof(StaticASTEntry) == 140,
    "StaticASTEntry size mismatch: expected 140, got " & $sizeof(StaticASTEntry)

# ─── BSS Singleton ───────────────────────────────────────────────────────────

var globalPipelineCtx* {.global.}: PipelineContext
  ## The singleton pipeline context. Lives in .bss segment.
  ## Access via `addr globalPipelineCtx` for noSideEffect compatibility.

{.pop.}
