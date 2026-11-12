## axiom_import_sandbox.nim — Compile-time Import Sandbox for hash_kernel.
##
## Restricts which modules may import hash_kernel. Only whitelisted
## modules (SSOT itself, macro definitions, hash accessors, manifest
## codegen, CEGAR cache, boot compiler integrity) are permitted.
##
## Usage:
##   enforceHashImportPolicy("src/core/crypto/hash_consolidation.nim")
##
## When axiomStrict is defined, violations are hard errors.
## Otherwise they emit warnings.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[macros, strutils, os]

const allowedHashImporters* = [
  "hash_kernel",
  "hash_consolidation",
  "manifest_provider",
  "gate_registry",
  "ast_hash",
  "axiom_boot_compiler",
]

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
macro enforceHashImportPolicy*(modulePath: static string): untyped =
  ## Compile-time gate: read modulePath, parse its AST, and flag any
  ## import of hash_kernel by a module not in allowedHashImporters.
  let content = staticRead(modulePath)
  let ast = parseStmt(content)
  let moduleName = modulePath.extractFilename.changeFileExt("")

  if moduleName notin allowedHashImporters:
    for node in ast:
      if node.kind == nnkImportStmt:
        for imported in node:
          let name = $imported
          if name == "hash_kernel" or name == "core/crypto/hash_kernel" or
             name.endsWith("/hash_kernel"):
            when defined(axiomStrict):
              error("IMPORT SANDBOX VIOLATION: '" & moduleName &
                    "' must not import hash_kernel.", node)
            else:
              warning("IMPORT SANDBOX WARNING: '" & moduleName &
                      "' imports hash_kernel.", node)
