## tools/shared/effect_classifier.nim
## Lightweight I/O effect classification for module paths.
## Extracted from effect_queries.nim seed logic (isIoModuleOrHint).
##
## Dependencies: std/[strutils, sets] only. No src/ imports.
## Used by: tools/hermetic_build, tools/axiom_validator

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[strutils, sets]

type
  EffectKind* = enum
    ekPure        ## No side effects
    ekIo          ## File I/O, general I/O
    ekNetwork     ## Network communication
    ekProcess     ## External process execution
    ekMutable     ## Global mutable state

  ModuleEffect* = object
    path*: string
    kind*: EffectKind
    reason*: string  ## Why this classification was assigned

const
  ## Path patterns that indicate I/O modules.
  ## These are heuristic — L2 (compile-time) provides definitive classification
  ## via {.axiomEffect.} and {.tags.} pragmas.
  ioPathPatterns* = [
    "attestation", "audit_store", "evidence_store", "file_ops",
    "gate_memo", "log", "logger", "manifest", "output", "persist",
    "storage", "writer", "deploy", "backup", "archive"
  ]

  networkPathPatterns* = [
    "http", "socket", "websocket", "grpc", "rest_api", "client",
    "fetch", "download", "upload", "remote", "sync_utils_process"
  ]

  processPathPatterns* = [
    "exec", "spawn", "process", "subprocess", "shell", "cmd",
    "osproc", "z3_pool", "lean_runner"
  ]

  mutableStatePatterns* = [
    "global_state", "shared_state", "singleton", "cache_epoch",
    "counter", "registry", "mutable"
  ]

func classifyByPath*(modulePath: string): EffectKind =
  ## Classify a module's effect by its file path.
  ## Returns ekPure if no I/O pattern matches.
  let lowerPath = modulePath.toLower()

  for pattern in processPathPatterns:
    if pattern in lowerPath:
      return ekProcess

  for pattern in networkPathPatterns:
    if pattern in lowerPath:
      return ekNetwork

  for pattern in ioPathPatterns:
    if pattern in lowerPath:
      return ekIo

  for pattern in mutableStatePatterns:
    if pattern in lowerPath:
      return ekMutable

  ekPure

func isIoModule*(modulePath: string): bool =
  ## Quick check: does this module likely perform I/O?
  classifyByPath(modulePath) != ekPure

func tagsForEffect*(kind: EffectKind): seq[string] =
  ## Map EffectKind to Nim {.tags.} type names.
  ## These must match the types defined in src/core/pure/hermetic_effects.nim.
  case kind
  of ekPure: @[]
  of ekIo: @["FileIO"]
  of ekNetwork: @["NetworkIO"]
  of ekProcess: @["ProcessExec"]
  of ekMutable: @["MutableState"]

func axiomEffectFor*(kind: EffectKind): string =
  ## Map EffectKind to {.axiomEffect.} pragma value.
  case kind
  of ekPure: "Pure"
  of ekIo, ekNetwork, ekProcess, ekMutable: "IoEffect"
