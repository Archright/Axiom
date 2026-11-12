# CLI Surface Verification Artifacts (EDC)

## Sub-task 1: Dispatch Chain Tracing

### Evidence A: planAxActions branching for `ax prove`
```
File: src/cli/action_plan_cli.nim
Lines: 157-162
```

```nim
of axSubcommandProve:
    if shouldUseAxProofShortcut(subArgs):
      result.add(CliAction(kind: cliRunAxProofShortcut, args: subArgs))
      return
    result.add(dispatchCommandAction(cliCommandVerify, normalizeAxVerifyAliasArgs("prove", subArgs)))
    return
```

**Verdict**: `ax prove` branches based on `shouldUseAxProofShortcut(subArgs)`.

### Evidence B: shouldUseAxProofShortcut logic
```
File: src/cli/ax_workflow_shortcuts.nim
Lines: 58-68
```

```nim
func shouldUseAxProofShortcut*(args: seq[string]): bool {.nosideeffect.} =
  if args.anyIt(it == "--payload-file"):
    return false
  if args.len == 0:
    return true
  args.anyIt(it == "--limit") or args.anyIt(it == "--state-file") or
    args.anyIt(it == "--vault-dir") or args.anyIt(it == "--jobs" or it == "-j") or
    args.anyIt(it == "--json") or args.anyIt(not isCliOptionToken(it)) or
    args.anyIt(it == "--full" or it == "--retry-failed" or it == "--heal" or
      it == "--formal-only" or it == "--single-thread" or it == "--require-perfect-asi" or
      it == "--continue-on-error" or it == "--graph-cache" or it == "--no-graph-cache")
```

**Verdict**: Returns `true` for `--full`, `--heal`, `--retry-failed`, positional args, and most common flags. Only `--payload-file` returns `false`.

### Evidence C: normalizeAxVerifyAliasArgs transforms "prove" to "workflow"
```
File: src/cli/action_plan_cli.nim
Lines: 84-91
```

```nim
func normalizeAxVerifyAliasArgs*(subcommand: string; args: seq[string]): seq[string] {.nosideeffect.} =
  case subcommand
  of "prove":
    @["workflow"] & args
```

**Verdict**: Non-shortcut `ax prove` becomes `ax verify workflow <args>`.

## Sub-task 2: Verify the Disconnect

### Evidence D: runAxProveShortcutCli only calls analyzeTopologySourceRoot
```
File: src/cli/wf_runners.nim
Lines: 138-179
```

Key excerpt (lines 145-156):
```nim
  let analysisRes = analyzeTopologySourceRoot(
    sourceRoot,
    queueLimit = flags.limit,
    queueLimitExplicit = flags.limit > 0,
    diagnosisDepth = 0,
    diagnosisDepthExplicit = false
  )
```

**Verdict**: The function never calls `runBatchUapOrchestration`, `runUniversalAcceptancePipeline`, or `runUniversalAcceptanceWorkflow`.

### Evidence E: grep confirms zero UAP references in wf_runners.nim
```bash
$ grep -n "runBatchUapOrchestration\|runUniversalAcceptancePipeline" src/cli/wf_runners.nim
```
Output: (empty)

**Verdict**: CONFIRMED — zero references to UAP engine in `wf_runners.nim`.

### Evidence F: flags.executionMode is never consumed in runAxProveShortcutCli
```bash
$ grep -n "executionMode\|flags\." src/cli/wf_runners.nim
```
Key output:
```
42:func buildIntegratedHealArgs(
71:proc defaultResolveSourceRootFromFolderContext(
96:let runAxScanShortcutCli* = proc (
138:let runAxProveShortcutCli* = proc (
139:  args: seq[string];
140:  cwdOverride: string = "";
141:  shortcutStatePathOverride: string = ""
142:): Result[AxCommandCliResult, string] =
143:  let flagsRes = parseAxProveFlags(args)
144:  if flagsRes.isErr():
145:    return err(flagsRes.error)
146:  let flags = flagsRes.get()
147:  let sourceRootRes = resolveSourceRootFromFolderContext(flags.targetDirectory, cwdOverride)
```

Lines 143-147 parse flags but never reference `flags.executionMode`.

**Verdict**: CONFIRMED — `executionMode` is parsed but ignored.

## Sub-task 3: Check for Indirect Invocation Paths

### Evidence G: runAxProveShortcutCli does not spawn subprocesses
```bash
$ grep -n "startProcess\|execProcess\|execCmd\|runAxHealCli\|cmdVerifyWorkflow" src/cli/wf_runners.nim
```
Output: (empty)

**Verdict**: No subprocess spawning, no heal bridge, no verify bridge.

### Evidence H: action_interpreter_cli dispatches cliRunAxProofShortcut directly
```
File: src/cli/action_interpreter_cli.nim
Lines: 45-46
```

```nim
    of cliRunAxProofShortcut:
      emitAxShortcutResult(runAxProveShortcutCli(action.args), action.args)
```

**Verdict**: Direct dispatch to shortcut runner with no intermediate branching.

## Sub-task 4: Exact Disconnect Line

**Disconnect occurs at `src/cli/action_plan_cli.nim:158`**:
```nim
if shouldUseAxProofShortcut(subArgs):
```

When this condition is `true` (which it is for `--full`, `--heal`, `--retry-failed`, positional args, etc.), the code takes the shortcut path at line 159 and **returns immediately** without ever reaching the `cliCommandVerify` path at line 161.

The `cliCommandVerify` path (line 161) is the ONLY path that leads to `cmdVerifyWorkflow` → `runBatchUapOrchestration` → `runUniversalAcceptancePipeline`. It is unreachable for all common `ax prove` invocations.

## Overall Verdict: CRITICAL DISCONNECT CONFIRMED

| Test | Result |
|---|---|
| Dispatch chain traced | PASS |
| Shortcut path bypasses UAP | PASS (confirmed) |
| `flags.executionMode` ignored | PASS (confirmed) |
| No indirect UAP invocation | PASS (confirmed) |
| Exact disconnect line identified | PASS (line 158, action_plan_cli.nim) |

**Conclusion**: `ax prove` is structurally disconnected from the 4-layer UAP engine at the CLI planning layer. The `--full`, `--heal`, and `--retry-failed` flags paradoxically force the shortcut (topology-only) path instead of the pipeline path.
