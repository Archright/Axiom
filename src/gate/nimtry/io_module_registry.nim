import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

import std/strutils
import std/tables

## I/O Module Registry — SSOT for stdlib modules with side effects.
## Used by safety-proc-purity query to identify procs that MUST remain proc.
## Also hosts effect_hints loaded from architecture_policy.lock.

const ioModules*: seq[string] = @[
  # File I/O
  "os", "syncio", "memfiles",
  # Process I/O
  "osproc",
  # Stream I/O
  "streams",
  # Terminal I/O
  "terminal",
  # Network I/O
  "net", "asyncnet", "asynchttpserver", "httpclient", "nativesockets",
  # Async I/O
  "asyncdispatch", "selectors",
  # Thread I/O
  "locks",
  # Project I/O boundary modules — genuine subprocess/file I/O. Registered so
  # that bare-name collision resolution (deterministic path-sorted) never
  # misclassifies their procs as pure: git_operations.execCmdEx, plumbing git
  # wrappers, workspace receipt git hash, lean replay subprocess, file readers.
  "git_operations.nim",
  "plumbing.nim",
  "workspace_receipt.nim",
  "fail_secure_state.nim",
  "lean_replay.nim",
  "the_judge_eval.nim",
  "documentation_first_gate.nim",
  "nim_check_runner.nim",
]

const effectHintModules*: Table[string, string] = {
  # Module-level effect hints from architecture_policy.lock [effect_hints].
  # These modules perform FFI or I/O boundary work even if they do not import
  # the stdlib I/O modules listed above.
  "src/core/parsers/tree_sitter_ffi.nim": "io",
  "core/parsers/tree_sitter_ffi.nim": "io",
  "tree_sitter_ffi.nim": "io",
  "src/core/parsers/tree_sitter/types.nim": "io",
  "core/parsers/tree_sitter/types.nim": "io",
  "tree_sitter/types.nim": "io",
  "src/core/parsers/tree_sitter/bindings.nim": "io",
  "core/parsers/tree_sitter/bindings.nim": "io",
  "tree_sitter/bindings.nim": "io",
  "src/core/parsers/tree_sitter/node.nim": "io",
  "core/parsers/tree_sitter/node.nim": "io",
  "tree_sitter/node.nim": "io",
  "src/core/parsers/tree_sitter/cache.nim": "io",
  "core/parsers/tree_sitter/cache.nim": "io",
  "tree_sitter/cache.nim": "io",
  "src/core/parsers/tree_sitter/nodes.nim": "io",
  "core/parsers/tree_sitter/nodes.nim": "io",
  "tree_sitter/nodes.nim": "io",
  "src/core/sync/sync_utils_resource.nim": "io",
  "core/sync/sync_utils_resource.nim": "io",
  "sync_utils_resource.nim": "io",
  "src/core/sync/sync_utils_process.nim": "io",
  "core/sync/sync_utils_process.nim": "io",
  "sync_utils_process.nim": "io",
  "src/core/trusted/stdlib_shield.nim": "io",
  "core/trusted/stdlib_shield.nim": "io",
  "stdlib_shield.nim": "io",
  "src/core/trusted/effect_shim.nim": "io",
  "core/trusted/effect_shim.nim": "io",
  "effect_shim.nim": "io",
}.toTable

func isIoModule*(modulePath: string): bool {.raises: [].} =
  ## Check if a module path refers to a stdlib I/O module.
  ## Matches both full paths ("std/os") and bare names ("os").
  let bare = modulePath.split("/")[^1]
  bare in ioModules

func hasEffectHint*(modulePath: string; hint: string): bool {.raises: [].} =
  effectHintModules.getOrDefault(modulePath, "") == hint

func isIoModuleOrHint*(modulePath: string): bool {.raises: [].} =
  isIoModule(modulePath) or hasEffectHint(modulePath, "io")

{.pop.}
