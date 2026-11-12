import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Gate Manifest v2 — Declarative I/O Specification
##
## Bazel Action model: Action = {inputs, outputs, command, env}
## Nix model: "Declared = Exists" — undeclared inputs are blocked by namespace sandbox.
##
## Each GateManifest declares:
## - inputs: files/dirs this gate reads
## - outputs: files/dirs this gate writes
## - command: the execution command
## - env: explicit environment variables
## - fixedHash (on outputs): Nix fixed-output derivation model
##   empty = floating (determined after execution)
##   non-empty = fixed (must match after execution)

import std/[tables]

type
  ArtifactKind* = enum
    akFile          ## Single file
    akDir           ## Directory (recursive)
    akStdout        ## Captured stdout (saved as file)

  InputSpec* = object
    path*: string              ## VFS path or glob pattern
    kind*: ArtifactKind
    optional*: bool            ## true = not an error if missing

  OutputSpec* = object
    path*: string              ## Output path
    kind*: ArtifactKind
    fixedHash*: string         ## empty = floating (Nix CA), non-empty = fixed-output

  GateManifest* = object
    id*: string                ## Gate ID (matches GateDef.id)
    inputs*: seq[InputSpec]    ## All paths this gate reads
    outputs*: seq[OutputSpec]  ## All paths this gate writes
    command*: string           ## Execution command (included in Action Key)
    env*: seq[(string, string)] ## Environment variables (included in Action Key)
    pathManifestHash*: string  ## PATH manifest hash (from Wave 7A)
    sourceDateEpoch*: int64    ## Frozen timestamp (from Wave 7A)

# --- Constructors ---

func input*(path: string, kind: ArtifactKind = akFile,
            optional: bool = false): InputSpec {.raises: [].} =
  InputSpec(path: path, kind: kind, optional: optional)

func output*(path: string, kind: ArtifactKind = akFile,
             fixedHash: string = ""): OutputSpec {.raises: [].} =
  OutputSpec(path: path, kind: kind, fixedHash: fixedHash)

func manifest*(id: string, inputs: seq[InputSpec] = @[],
               outputs: seq[OutputSpec] = @[],
               command: string = "",
               env: seq[(string, string)] = @[]): GateManifest {.raises: [].} =
  GateManifest(id: id, inputs: inputs, outputs: outputs,
               command: command, env: env)

# --- Validation ---

func validateManifest*(m: GateManifest): seq[string] {.raises: [].} =
  ## Validate a manifest. Returns list of errors (empty = valid).
  result = @[]

  if m.id.len == 0:
    result.add("Manifest ID is empty")

  # Check for duplicate input paths
  var inputPaths: seq[string] = @[]
  for inp in m.inputs:
    if inp.path in inputPaths:
      result.add("Duplicate input path: " & inp.path)
    inputPaths.add(inp.path)

  # Check for duplicate output paths
  var outputPaths: seq[string] = @[]
  for ot in m.outputs:
    if ot.path in outputPaths:
      result.add("Duplicate output path: " & ot.path)
    outputPaths.add(ot.path)

  # Check for overlap between inputs and outputs
  for inp in m.inputs:
    for ot in m.outputs:
      if inp.path == ot.path:
        result.add("Path appears in both inputs and outputs: " & inp.path)

# --- Collision Detection Helpers ---

func outputPaths*(m: GateManifest): seq[string] {.raises: [].} =
  ## Extract all output paths from manifest.
  result = @[]
  for ot in m.outputs:
    result.add(ot.path)

func inputPaths*(m: GateManifest): seq[string] {.raises: [].} =
  ## Extract all input paths from manifest.
  result = @[]
  for inp in m.inputs:
    result.add(inp.path)

func hasOutputOverlap*(a, b: GateManifest): bool {.raises: [].} =
  ## Check if two manifests write to the same output path.
  let aOutputs = a.outputPaths()
  let bOutputs = b.outputPaths()
  for aPath in aOutputs:
    if aPath in bOutputs:
      return true
  false

func hasInputOutputDependency*(producer, consumer: GateManifest): bool {.raises: [].} =
  ## Check if producer's outputs overlap with consumer's inputs.
  ## If true, consumer must declare producer in its 'after' edges.
  let producerOutputs = producer.outputPaths()
  let consumerInputs = consumer.inputPaths()
  for ot in producerOutputs:
    if ot in consumerInputs:
      return true
  false

func findMissingEdges*(manifests: seq[GateManifest],
                       afterEdges: Table[string, seq[string]]): seq[string] {.raises: [].} =
  ## Find all missing dependency edges.
  ## If A produces output that B reads, but A ∉ B.after → error.
  result = @[]
  for i in 0..<manifests.len:
    for j in 0..<manifests.len:
      if i == j: continue
      let producer = manifests[i]
      let consumer = manifests[j]
      if hasInputOutputDependency(producer, consumer):
        let consumerEdges = afterEdges.getOrDefault(consumer.id, @[])
        if producer.id notin consumerEdges:
          result.add("Missing edge: " & producer.id & " → " & consumer.id &
                     " (output overlap with input)")

func findOutputCollisions*(manifests: seq[GateManifest],
                           afterEdges: Table[string, seq[string]]): seq[string] {.raises: [].} =
  ## Find output path collisions without proper ordering.
  result = @[]
  for i in 0..<manifests.len:
    for j in (i+1)..<manifests.len:
      if hasOutputOverlap(manifests[i], manifests[j]):
        let a = manifests[i]
        let b = manifests[j]
        let bEdges = afterEdges.getOrDefault(b.id, @[])
        let aEdges = afterEdges.getOrDefault(a.id, @[])
        if a.id notin bEdges and b.id notin aEdges:
          result.add("Output collision: " & a.id & " ↔ " & b.id &
                     " (no ordering edge)")

{.pop.}
