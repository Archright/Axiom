import core/trusted/layer_declaration
axiomLayer "domain"
import std/os
import std/sets
import std/strutils
import std/options
import std/algorithm
import core/parser_utils
import core/parsers/pnode_nav
import compiler/ast
{.push raises: [CatchableError].}
import core/utils/file_utils
# axiomIoBoundary

type FunctionRef* = object
  name*: string
  modulePath*: string
  sourcePath*: string
  irHash*: string

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeIdentForFilename*(raw: string): string {.raises: [].} =
  var s = raw
  s = s.replace("\\", "_BSL_")
  s = s.replace("/", "_SL_")
  s = s.replace("[", "_LBR_")
  s = s.replace("]", "_RBR_")
  s = s.replace("(", "_LPAR_")
  s = s.replace(")", "_RPAR_")
  s = s.replace(",", "_COM_")
  s = s.replace(".", "_")
  s = s.replace(" ", "_SPC_")
  s = s.replace("-", "_DASH_")
  s = s.replace("%", "_percent_")
  s = s.replace("$", "_dollar_")
  s = s.replace("?", "_qmark_")
  result = s

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func normalizeModulePath*(path: string; repoRoot: string): string =
  let normalizedPath = path.replace("\\", "/")
  var normalizedRoot = repoRoot.replace("\\", "/")
  while normalizedRoot.len > 0 and normalizedRoot[^1] == '/':
    normalizedRoot.setLen(normalizedRoot.len - 1)
  if normalizedRoot.len == 0:
    return normalizedPath.strip(chars = {'/'})
  let prefix = normalizedRoot & "/"
  if normalizedPath.startsWith(prefix):
    return normalizedPath[prefix.len .. ^1]
  normalizedPath.strip(chars = {'/'})

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func sanitizeLeanIdent*(raw: string): string {.raises: [].} =
  var normalized = newStringOfCap(raw.len + 8)
  for ch in raw:
    if ch.isAlphaNumeric or ch == '_':
      normalized.add(ch)
    else:
      normalized.add('_')
  while normalized.find("__") >= 0:
    normalized = normalized.replace("__", "_")
  normalized.strip(chars = {'_'})

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
proc collectFunctions*(srcRoot: string): seq[FunctionRef]  =
  var seen = initHashSet[string]()
  for path in walkDirRec(srcRoot):
    if not path.endsWith(".nim"):
      continue
    let modulePath = normalizeModulePath(path, srcRoot)
    let source = readFileSafe(path)
    try:
      let ast = parseStringAST(source)
      if not ast.isNil:
        for decl in findNodesP(ast, ProcDefKinds):
          if decl.len > 0 and not decl[0].isNil:
            let nameNodeOpt = findFirstNodeP(decl[0], {nkIdent, nkSym})
            if nameNodeOpt.isSome:
              let fn = if nameNodeOpt.get.kind == nkIdent:
                          nameNodeOpt.get.ident.s
                        elif nameNodeOpt.get.kind == nkSym:
                          nameNodeOpt.get.sym.name.s
                        else:
                          ""
              if fn.len == 0:
                continue
              let key = modulePath & "#" & fn
              if seen.contains(key):
                continue
              seen.incl(key)
              result.add(FunctionRef(name: fn, modulePath: modulePath, sourcePath: path))
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
  result = result.sortedByIt(it.modulePath & "#" & it.name)

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func buildTheoremName*(fn: FunctionRef): string {.raises: [].} =
  sanitizeLeanIdent(fn.modulePath.replace(".nim", "")) & "_" & fn.name & "_logic_integrity"

{.pop.}
