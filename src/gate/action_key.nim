import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Action Key — "함수의 지문"
##
## Bazel model: Action Key encodes ALL aspects that could affect output.
## Identity = Hash(inputs ∪ path_manifest ∪ source_date ∪ command ∪ env)
##
## Changes that invalidate cache:
## - Input file content changes (inputHashes)
## - PATH tool version changes (pathManifestHash)
## - Build timestamp changes (sourceDateEpoch)
## - Command changes (command)
## - Environment variable changes (env)

import std/[tables, algorithm, strutils]
import checksums/sha2

type
  ActionKey* = distinct string
    ## Deterministic hash encoding all action-affecting aspects.
    ## Bazel model: identical inputs → identical key → cache hit.

proc `$`*(key: ActionKey): string = string(key)

proc computeHash*(data: string): string =
  ## SHA-256 hash of input data, returned as lowercase hex string.
  $secureHash(Sha_256, data)

proc computeActionKey*(
    inputHashes: Table[string, string],    # path → content hash
    pathManifestHash: string,              # PATH binary manifest hash
    sourceDateEpoch: int64,                # frozen timestamp
    command: string,                       # execution command
    env: seq[(string, string)]             # sorted env vars
): ActionKey =
  ## Compute deterministic action key.
  ## All inputs sorted for determinism.
  var parts: seq[string] = @[]

  # Input file hashes (sorted by path)
  var sortedPaths: seq[string] = @[]
  for path in inputHashes.keys:
    sortedPaths.add(path)
  sortedPaths.sort()
  for path in sortedPaths:
    parts.add("input:" & path & "=" & inputHashes.getOrDefault(path))

  # PATH manifest (toolchain identity)
  parts.add("path_manifest:" & pathManifestHash)

  # Frozen timestamp
  parts.add("source_date:" & $sourceDateEpoch)

  # Command
  parts.add("command:" & command)

  # Environment variables (caller should sort)
  for (k, v) in env:
    parts.add("env:" & k & "=" & v)

  ActionKey(computeHash(parts.join("\n")))

proc computeActionKeyFromManifest*(
    manifestInputs: seq[string],           # declared input paths
    manifestOutputs: seq[string],          # declared output paths
    command: string,
    env: seq[(string, string)],
    pathManifestHash: string = "",
    sourceDateEpoch: int64 = 0
): ActionKey =
  ## Simplified version for manifest-based computation.
  ## Used when input hashes are not yet available.
  var parts: seq[string] = @[]
  for path in sorted(manifestInputs):
    parts.add("decl_input:" & path)
  for path in sorted(manifestOutputs):
    parts.add("decl_output:" & path)
  parts.add("path_manifest:" & pathManifestHash)
  parts.add("source_date:" & $sourceDateEpoch)
  parts.add("command:" & command)
  for (k, v) in env:
    parts.add("env:" & k & "=" & v)
  ActionKey(computeHash(parts.join("\n")))

proc shortKey*(key: ActionKey, len: int = 16): string =
  ## First N characters of key for display / directory naming.
  let s = string(key)
  s[0 ..< min(len, s.len)]

{.pop.}

