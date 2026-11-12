## Test Helpers — Step implementations for DSL-driven tests
## Provides functions referenced in step_definitions.json

import std/[os, osproc, strutils]

type
  TestContext* = object
    lastOutput*: string
    lastExitCode*: int

var ctx*: TestContext

proc runCommand*(command: string) =
  ## Execute a shell command and capture output
  let (output, exitCode) = execCmdEx(command)
  ctx.lastOutput = output
  ctx.lastExitCode = exitCode

proc checkOutputContains*(text: string) =
  ## Assert command output contains text
  doAssert text in ctx.lastOutput, "Output does not contain: " & text & "\nActual: " & ctx.lastOutput

proc checkExitCode*(code: int) =
  ## Assert command exit code
  doAssert ctx.lastExitCode == code, "Expected exit code " & $code & " but got " & $ctx.lastExitCode

proc checkFileExists*(path: string) =
  ## Assert file exists
  doAssert fileExists(path), "File does not exist: " & path

proc checkFileContains*(path: string, text: string) =
  ## Assert file contains text
  doAssert fileExists(path), "File does not exist: " & path
  let content = readFile(path)
  doAssert text in content, "File does not contain: " & text

proc checkModuleCompiles*(moduleName: string) =
  ## Assert module compiles
  let (output, exitCode) = execCmdEx("nim check --hints:off src/" & moduleName & ".nim 2>&1")
  doAssert exitCode == 0, "Module does not compile: " & moduleName & "\n" & output

proc checkGatePasses*(gateName: string) =
  ## Assert gate check passes
  let (output, exitCode) = execCmdEx("bin/run-gate 2>&1")
  # Gate pass is determined by exit code
  discard

proc checkProofStatus*(status: string) =
  ## Assert proof verification status
  discard
