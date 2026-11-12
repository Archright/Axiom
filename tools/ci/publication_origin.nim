## publication_origin.nim — the single origin-declaration model shared by
## the publication-integrity evaluators.
##
## compliance/provenance/source-origin.yml is one SSOT consumed by several
## gate jobs (provenance-validate, license-scan). This module is the ONE
## parser of that file so two tools can never diverge on declaration
## semantics (AGENTS.md §1: duplicate semantic state is forbidden).
##
## Matching semantics — kept in lockstep with the header comment of
## compliance/provenance/source-origin.yml:
##   - "dir/**" matches the directory itself and everything under it;
##   - an exact path matches exactly that file;
##   - a declaration's "exclude" list (exact paths) removes those files
##     from that declaration's scope — an excluded file must be covered by
##     another declaration or it is UNDECLARED (exclusion without
##     re-declaration stays a hole, never a pass);
##   - a file MAY match several rules only if ALL matching rules agree on
##     (origin, license) — a disagreement is an INCONSISTENT verdict (the
##     provenance validator enforces it), never silently resolved.
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[options, strutils]
import core/trusted/layer_declaration
import core/results
import tools/ci/publication_yaml

axiomLayer "tools"

type
  Declaration* = object
    path*: string
    origin*: string
    source*: string
    copyright*: string
    license*: string
    exclude*: seq[string]

proc loadDeclarations*(node: YNode): Result[seq[Declaration], string] =
  ## Parse the `declarations:` list of a parsed source-origin.yml root.
  if node.kind != yMap:
    return err("declarations root is not a mapping")
  var decls: seq[Declaration] = @[]
  for d in node.yListMaps("declarations"):
    let path = d.yStr("path")
    let origin = d.yStr("origin")
    if path.len == 0:
      return err("declaration without path")
    if origin.len == 0:
      return err("declaration without origin: " & path)
    decls.add Declaration(
      path: path, origin: origin,
      source: d.yStr("source"),
      copyright: d.yStr("copyright"),
      license: d.yStr("license"),
      exclude: d.yListStrs("exclude"))
  if decls.len == 0:
    return err("no declarations found")
  ok(decls)

proc matchesPath*(decl: Declaration, file: string): bool =
  ## `dir/**` matches the directory itself and everything under it; any
  ## other declaration is an exact path match. A file listed in the
  ## declaration's `exclude` list does not match that declaration at all.
  if file in decl.exclude:
    return false
  if decl.path.endsWith("/**"):
    let dir = decl.path[0 ..< decl.path.len - 3]
    return file == dir or file.startsWith(dir & "/")
  return decl.path == file

proc firstMatch*(decls: seq[Declaration], file: string): Option[Declaration] =
  ## First declaration whose scope covers `file` (rule order is the
  ## tie-break; the provenance validator separately fails DISAGREEING
  ## overlaps, so order only decides among agreeing rules).
  for d in decls:
    if d.matchesPath(file):
      return some(d)
  none(Declaration)
