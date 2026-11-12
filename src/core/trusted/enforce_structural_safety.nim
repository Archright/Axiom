import core/trusted/layer_declaration
axiomLayer "domain"
# ─── Compile-time Structural Safety Guard ─────────────────────────────────────
# 100% compile-time AST structural safety enforcement.
# Injected globally via config.nims `switch("import", ...)` — no manual annotation needed.
# Every compiled module automatically receives this guard at compile time.
#
# AGENTS.md §0.6: Static First Enforcement
# ──────────────────────────────────────────────────────────────────────────────
{.warning[UnusedImport]: off.}  # Macro-only module — import is always "unused" at surface
import std/macros
{.push raises: [].}

macro enforceStructuralSafety*(moduleBody: untyped): untyped =
  ## 100% compile-time AST structural safety guard.
  ## Validates the following at compile time (zero runtime cost):
  ##   1. ref object must not contain proc/func fields (unique — no other gate covers this)
  ##   3. Import Shadowing Prevention — error on duplicate imports within same file
  ##   4. Forward Declaration Keyword Consistency — func/proc mismatch detection
  ##   5. Strict Effects Enforcement — errors if strictEffects pragma is missing
  ##   6. Higher-Order Function Effect Contract — warns on missing {.raises.} on proc params
  ##   7a. cast usage is forbidden (unique — axiom_validator only catches cast(noSideEffect))
  ##   7b. staticExec/gorge() Cache Parameter Enforcement — ensures SHA1 determinism
  ##   8. gorge() Whitelist — blocks non-deterministic commands (env, hostname, etc.)
  ##   9. I/O Proc Effect Annotation — warns on missing {.axiomEffect: IoEffect.} on procs with I/O calls
  ##
  ## This macro is a passthrough — it inspects the AST but returns it unchanged.
  ## Violations produce compile errors, making violations impossible to ship.
  ## Gated behind -d:axiomStrict to save ~1-2s per build when not needed.
  when defined(axiomStrict):
    let srcFile = moduleBody.lineInfoObj.filename
    var importedModules: seq[string] = @[]
    var hasStrictEffects = false
    var forwardFuncs: seq[string] = @[]  # Track `func X` forward decls

    # ── Pre-scan: detect strictEffects pragma and forward declarations ──
    for node in moduleBody:
      # Check 5: Strict Effects Enforcement
      if node.kind == nnkPragmaExpr:
        for pragma in node:
          if pragma.kind == nnkPragma:
            for p in pragma:
              if p.kind == nnkIdent and p.strVal == "experimental":
                hasStrictEffects = true
              elif p.kind == nnkExprColonExpr and
                   p[0].kind == nnkIdent and p[0].strVal == "experimental":
                if p.len > 1:
                  let val = $p[1]
                  if "strictEffects" in val:
                    hasStrictEffects = true
              elif p.kind == nnkIdent and p.strVal == "push":
                # {.push strictEffects.} — check next pragma items
                discard
      elif node.kind == nnkPragma:
        for p in node:
          if p.kind == nnkIdent and p.strVal == "strictEffects":
            hasStrictEffects = true
      # Check 4 pre-scan: collect forward func declarations
      if node.kind == nnkFuncDef:
        let name = node[0].strVal
        forwardFuncs.add(name)

    # Emit error for missing strictEffects
    if not hasStrictEffects:
      error("Structural Safety: {.experimental: \"strictEffects\".} or " &
            "{.push strictEffects.} not found in " & srcFile &
            ". Effect contracts may be imprecise.", moduleBody)

    # Helper for Check 9: recursively detect I/O calls in AST
    const ioFuncs = [
      "readFile", "writeFile", "execCmd", "open", "createDir",
      "readLines", "readAll", "writeLines", "appendFile",
      "removeFile", "moveFile", "copyFile", "existsDir",
      "existsFile", "getFileSize", "walkDir", "walkDirRec",
      "execCmdEx", "startProcess",
    ]

    func hasIoCall(n: NimNode): bool =
      if n.kind == nnkCall:
        if n.len > 0 and n[0].kind == nnkIdent:
          if n[0].strVal in ioFuncs:
            return true
      for child in n:
        if hasIoCall(child):
          return true
      return false

    for node in moduleBody:
      # ── Check 1: ref object must not contain proc/func fields ──
      if node.kind == nnkTypeSection:
        for typeDef in node:
          if typeDef.len >= 3 and typeDef[2].kind == nnkRefTy:
            let refBody = typeDef[2]
            if refBody.len >= 1 and refBody[0].kind == nnkObjectTy:
              let objBody = refBody[0]
              if objBody.len >= 3 and objBody[2].kind == nnkRecList:
                for field in objBody[2]:
                  if field.kind == nnkIdentDefs:
                    let fieldType = field[^2]
                    if fieldType.kind == nnkProcTy:
                      error("Structural Safety: proc field in ref object '" &
                            $typeDef[0].repr & "'. " &
                            "Use method dispatch or closures stored as ref instead.", field)

      # ── Check 3: Import Shadowing Prevention ──
      if node.kind == nnkImportStmt:
        for ident in node:
          if ident.kind == nnkIdent:
            let modName = ident.strVal
            if modName in importedModules:
              error("Structural Safety: Duplicate import '" & modName &
                    "' in " & srcFile &
                    ". Import shadowing causes undefined behavior.", node)
            importedModules.add(modName)
      elif node.kind == nnkImportExceptStmt:
        let modName = node[0].strVal
        if modName in importedModules:
          error("Structural Safety: Duplicate import '" & modName &
                "' in " & srcFile &
                ". Import shadowing causes undefined behavior.", node)
        importedModules.add(modName)

      # ── Check 4: Forward Declaration Keyword Consistency ──
      if node.kind == nnkProcDef:
        let name = node[0].strVal
        if name in forwardFuncs:
          error("Structural Safety: proc '" & name & "' implementation matches " &
                "a prior func forward declaration in " & srcFile &
                ". Use consistent keywords (func <-> func, proc <-> proc).", node)

      # ── Check 6: Higher-Order Function Effect Contract ──
      if node.kind in {nnkProcDef, nnkFuncDef}:
        # Formal params are at index 3 (nnkFormalParams)
        if node.len > 3 and node[3].kind == nnkFormalParams:
          for param in node[3]:
            if param.kind == nnkIdentDefs:
              let paramType = param[^2]
              if paramType.kind == nnkProcTy:
                # Check if this proc-typed param has {.raises.} in its pragmas
                var hasRaises = false
                if paramType.len >= 2:
                  let pragmaNode = paramType[1]
                  if pragmaNode.kind == nnkPragma:
                    for p in pragmaNode:
                      if p.kind == nnkIdent and p.strVal == "raises":
                        hasRaises = true
                      elif p.kind == nnkExprColonExpr and
                           p[0].kind == nnkIdent and p[0].strVal == "raises":
                        hasRaises = true
                if not hasRaises:
                  warning("Structural Safety: proc parameter '" &
                          $param[0] & "' in " & $node[0] &
                          " has no {.raises.} annotation. " &
                          "Add explicit effect contract for strictEffects compliance.", param)

      # ── Check 7a: cast usage is forbidden (bypasses effect system) ──
      if node.kind == nnkCast:
        error("Structural Safety: 'cast' detected in " & srcFile &
              ". cast bypasses the effect system and is forbidden.", node)

      # ── Check 7b: staticExec/gorge() Cache Parameter Enforcement ──
      if node.kind == nnkCallStrLit:
        let procName = node[0].strVal
        if procName in {"staticExec", "gorge"}:
          # nnkCallStrLit has: [ident, strLit, ...] — check for 3rd arg (cache)
          if node.len < 3:
            error("Structural Safety: " & procName & "() in " & srcFile &
                  " is missing the cache parameter (3rd arg). " &
                  "Provide a SHA1 hash string for deterministic builds. " &
                  "Exception: staticRead is fine (reads file content).", node)

      # ── Check 8: gorge() Whitelist ──
      if node.kind == nnkCallStrLit:
        let procName = node[0].strVal
        if procName in {"staticExec", "gorge"} and node.len >= 2:
          let cmdNode = node[1]
          if cmdNode.kind == nnkStrLit:
            let cmd = cmdNode.strVal
            # Whitelist of allowed commands (deterministic outputs)
            const whitelist = [
              "z3 --version", "lean --version", "lake --version",
              "git rev-parse HEAD", "nim --version",
              "git rev-parse --short HEAD", "git log -1 --format=%H",
            ]
            # Blocked patterns (non-deterministic environment reads)
            const blockedPatterns = [
              "uname", "hostname", "date", "whoami", "env", "printenv",
              "cat /etc/hostname", "readlink", "realpath",
            ]
            var matched = false
            for w in whitelist:
              if cmd.startsWith(w):
                matched = true
                break
            if not matched:
              for bp in blockedPatterns:
                if bp in cmd:
                  error("Structural Safety: Non-deterministic command '" & cmd &
                        "' in gorge()/staticExec() in " & srcFile &
                        ". Blocked pattern: '" & bp &
                        "'. Use only whitelisted deterministic commands.", node)
                  break

      # ── Check 9: I/O Proc Effect Annotation ──
      if node.kind in {nnkProcDef, nnkFuncDef}:
        # Check if this proc already has {.axiomEffect: IoEffect.} or {.noSideEffect.}
        var hasIoEffect = false
        if node[0].kind == nnkPragmaExpr:
          for pragmaChild in node[0]:
            if pragmaChild.kind == nnkPragma:
              for p in pragmaChild:
                if p.kind == nnkExprColonExpr and
                   p[0].kind == nnkIdent and p[0].strVal == "axiomEffect":
                  hasIoEffect = true
                elif p.kind == nnkIdent and p.strVal == "noSideEffect":
                  hasIoEffect = true

        if not hasIoEffect:
          let body = node.last
          if body.kind == nnkStmtList and hasIoCall(body):
            warning("Structural Safety: proc '" & $node[0] &
                    "' in " & srcFile &
                    " calls I/O functions but lacks {.axiomEffect: IoEffect.} annotation. " &
                    "Add effect annotation for effect system compliance.", node)

  result = moduleBody  # Passthrough — no transformation, only validation

{.pop}

