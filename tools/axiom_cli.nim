## axiom_cli.nim — Strong-Typed Nim CLI Composer
##
## Deterministic assembly of `nim` CLI commands via typed NimArgs object.
## Eliminates string concatenation bugs and ensures correct flag ordering
## (--flags BEFORE source file, per Nim 2.2.10 parser constraint).
##
## Compile: nim c -o:bin/axiom-cli tools/axiom_cli.nim

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[strutils, strformat]

# ── Types ──────────────────────────────────────────────────────────────────────

type
  NimSubcommand* = enum
    cmdCheck = "check"
    cmdCompile = "c"
    cmdDoc = "doc"

  NimArgs* = object
    subcommand*: NimSubcommand
    flags*: seq[string]       ## --flag:value pairs (always emitted BEFORE targetFile)
    targetFile*: string       ## Source file path
    isolation*: bool          ## true → inject --skipParentCfg --skipUserCfg
    customNimcache*: string   ## If non-empty, add --nimcache:<path>

# ── Render ────────────────────────────────────────────────────────────────────

proc render*(args: NimArgs): string =
  ## Render NimArgs to a deterministic CLI string.
  ## Flag ordering: nim <subcommand> [isolation flags] [custom flags] [flags...] <target>
  ## This matches Nim 2.2.10's requirement: flags BEFORE source file.
  result = "nim " & $args.subcommand

  # Hermetic isolation flags (always first)
  if args.isolation:
    result &= " --skipParentCfg --skipUserCfg"

  # Custom nimcache (always second)
  if args.customNimcache.len > 0:
    result &= fmt" --nimcache:{args.customNimcache}"

  # User flags
  for flag in args.flags:
    result &= " " & flag

  # Target file (always last — Nim 2.2.10 constraint)
  if args.targetFile.len > 0:
    result &= " " & args.targetFile

# ── Convenience Constructors ──────────────────────────────────────────────────

proc checkArgs*(target: string, nimcache: string = "",
                isolation: bool = false): NimArgs =
  ## Create args for `nim check <target>`.
  result = NimArgs(
    subcommand: cmdCheck,
    targetFile: target,
    isolation: isolation,
    customNimcache: nimcache
  )

proc compileArgs*(target: string, nimcache: string = "",
                  extraFlags: seq[string] = @[],
                  isolation: bool = false): NimArgs =
  ## Create args for `nim c <target>`.
  result = NimArgs(
    subcommand: cmdCompile,
    targetFile: target,
    flags: extraFlags,
    isolation: isolation,
    customNimcache: nimcache
  )

# ── Validation ────────────────────────────────────────────────────────────────

proc validate*(args: NimArgs): seq[string] =
  ## Validate NimArgs. Returns list of errors (empty = valid).
  result = @[]
  if args.targetFile.len == 0:
    result.add("targetFile is empty")
  if args.subcommand == cmdCheck and args.targetFile.len == 0:
    result.add("check requires a target file")

{.pop.}
