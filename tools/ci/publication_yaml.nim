## publication_yaml.nim — restricted-YAML subset parser for the
## publication-integrity compliance policies.
##
## The compliance policies are authored in a DELIBERATELY restricted YAML
## subset (documented in each policy file's header):
##   - mappings of `key: "value"` pairs with quoted scalar values only;
##   - lists written as `- ` items (quoted scalars, or flat mappings whose
##     fields may themselves carry nested blocks);
##   - 2-space indentation per level; no anchors, no multi-line scalars,
##     no flow style, no document markers.
## Parsing this subset deterministically keeps the policy judgment free of
## an external YAML dependency (the repo's Language Ban posture: the
## execution layer is Nim only) while the files stay reviewable YAML.
##
## Anything outside the subset is a PARSE ERROR (fail-closed) — never a
## silent skip: a policy that cannot be parsed cannot be weakened by
## accident.
##
## Verdict surface (pure, no I/O):
##   parseRestrictedYaml(text) -> Result[YNode, string]
##   YNode = yStr | yList(seq[YNode]) | yMap(seq[(key, val)])
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[options, strutils]
import core/trusted/layer_declaration
import core/results

axiomLayer "tools"

type
  YNodeKind* = enum
    yStr
    yList
    yMap
  YNode* = object
    case kind*: YNodeKind
    of yStr: strVal*: string
    of yList: items*: seq[YNode]
    of yMap: fields*: seq[tuple[key: string, val: YNode]]

# ---------------------------------------------------------------------------
# Line-level scanning
# ---------------------------------------------------------------------------

type
  Line = object
    indent: int          ## spaces before content
    content: string      ## content after the indent (no trailing spaces)
    num: int             ## 1-based source line number

proc stripComment(line: string): string =
  ## A `#` starts a comment ONLY at line start (after indent) or when
  ## preceded by a space, and never inside a quoted scalar (the subset
  ## forbids `#` inside quotes — enforced by the quoting requirement).
  var inQuote = false
  for i, ch in line:
    if ch == '"':
      inQuote = not inQuote
    elif ch == '#' and not inQuote and (i == 0 or line[i-1] == ' '):
      return line[0 ..< i]
  return line

proc splitLines(text: string): seq[Line] =
  var idx = 0
  for raw in text.splitLines():
    inc idx
    if raw.len == 0:
      continue
    let noComment = stripComment(raw)
    var stripped = noComment
    # trailing spaces outside quotes — leading MUST be preserved (indent is
    # the block structure; strip() defaults leading=true, which flattens
    # every unquoted-end line to indent 0)
    if not stripped.endsWith('"'):
      stripped = stripped.strip(leading = false, trailing = true)
    let content0 = stripped
    var indent = 0
    while indent < content0.len and content0[indent] == ' ':
      inc indent
    let content = content0[indent ..^ 1]
    if content.len == 0:
      continue
    result.add Line(indent: indent, content: content, num: idx)

proc parseScalar(content: string): Result[YNode, string] =
  ## Quoted string scalar only. Unquoted scalars are a parse error —
  ## the subset requires quotes so no ambiguous bare token is ever
  ## silently interpreted.
  if content.len >= 2 and content[0] == '"' and content[^1] == '"':
    return ok(YNode(kind: yStr, strVal: content[1 ..^ 2]))
  err("not a quoted scalar (subset contract): " & content)

proc firstUnquotedColon(s: string): int =
  ## Index of the first ':' that appears BEFORE any opening quote — a
  ## `key:` prefix. -1 when none (the string is a pure scalar).
  for i, ch in s:
    if ch == '"':
      return -1
    if ch == ':':
      return i
  return -1

# ---------------------------------------------------------------------------
# Block parser
# ---------------------------------------------------------------------------

type
  Parser = object
    lines: seq[Line]
    pos: int

proc peek(p: Parser): Option[Line] =
  if p.pos < p.lines.len:
    some(p.lines[p.pos])
  else:
    none(Line)

proc next(p: var Parser): Line =
  result = p.lines[p.pos]
  inc p.pos

proc parseBlock(p: var Parser, indent: int): Result[YNode, string] =
  ## Parse one block whose lines all sit at `indent`:
  ##   - a LIST block: every line at `indent` starts with `- `;
  ##   - a MAPPING block: every line at `indent` is `key: "value"` or
  ##     `key:` (nested block at a deeper indent).
  ## List items that are mappings are parsed by REWRITING the item line in
  ## place to `indent+2` (dropping the `- ` prefix) and delegating to this
  ## same proc — the item's continuation fields then continue the mapping,
  ## and nested blocks under item fields work through the ordinary
  ## `'key:' + deeper block` rule.
  let head = p.peek().get()
  if head.content.startsWith("- "):
    var items: seq[YNode] = @[]
    while true:
      let cur = p.peek()
      if cur.isNone:
        break
      let l = cur.get()
      if l.indent != indent:
        break
      if l.content == "-":
        return err("bare '-' item at line " & $l.num & " (subset: '- ' with content)")
      if not l.content.startsWith("- "):
        return err("list item expected at line " & $l.num)
      let itemContent = l.content[2 ..^ 1]
      if itemContent.len == 0:
        return err("empty list item at line " & $l.num)
      # mapping item (a `key:` prefix before any quote) → rewrite + delegate
      if firstUnquotedColon(itemContent) >= 0:
        p.lines[p.pos] = Line(indent: indent + 2, content: itemContent, num: l.num)
        let m = p.parseBlock(indent + 2)
        if m.isErr:
          return m
        items.add(m.get)
      else:
        discard p.next()
        let scalarRes = parseScalar(itemContent)
        if scalarRes.isErr:
          return err("line " & $l.num & ": " & scalarRes.error)
        items.add(scalarRes.get)
    if items.len == 0:
      return err("empty list at line " & $head.num)
    return ok(YNode(kind: yList, items: items))
  # mapping block
  var fields: seq[tuple[key: string, val: YNode]] = @[]
  while true:
    let cur = p.peek()
    if cur.isNone:
      break
    let l = cur.get()
    if l.indent != indent:
      if l.indent > indent:
        return err("unexpected deeper indent at line " & $l.num)
      break
    if l.content.startsWith("- "):
      return err("list item where a mapping line was expected at line " & $l.num)
    let ci = firstUnquotedColon(l.content)
    if ci < 0:
      return err("mapping line must be 'key: \"value\"' or 'key:' at line " & $l.num)
    let key = l.content[0 ..< ci].strip()
    if key.len == 0:
      return err("empty mapping key at line " & $l.num)
    let rest = l.content[ci + 1 ..^ 1].strip()
    discard p.next()
    if rest.len == 0:
      # `key:` — nested block at a strictly deeper indent
      let nxt = p.peek()
      if nxt.isNone:
        return err("line " & $l.num & ": 'key:' with no nested block")
      let childIndent = nxt.get().indent
      if childIndent <= indent:
        return err("line " & $l.num & ": 'key:' without a deeper nested block")
      let child = p.parseBlock(childIndent)
      if child.isErr:
        return child
      fields.add((key, child.get))
    else:
      let valRes = parseScalar(rest)
      if valRes.isErr:
        return err("line " & $l.num & ": " & valRes.error)
      fields.add((key, valRes.get))
  if fields.len == 0:
    return err("empty mapping at line " & $head.num)
  return ok(YNode(kind: yMap, fields: fields))

proc parseRestrictedYaml*(text: string): Result[YNode, string] =
  ## Parse the restricted YAML subset. The top level must be a mapping.
  var p = Parser(lines: splitLines(text))
  if p.lines.len == 0:
    return err("empty document")
  if p.lines[0].indent != 0:
    return err("top-level indent must be 0 (line " & $p.lines[0].num & ")")
  let parsed = p.parseBlock(0)
  if parsed.isErr:
    return parsed
  if p.pos != p.lines.len:
    return err("trailing content at line " & $p.lines[p.pos].num)
  if parsed.get().kind != yMap:
    return err("top-level node must be a mapping")
  ok(parsed.get())

# ---------------------------------------------------------------------------
# Accessors
# ---------------------------------------------------------------------------

proc yGet*(node: YNode, key: string): Option[YNode] =
  if node.kind != yMap:
    return none(YNode)
  for f in node.fields:
    if f.key == key:
      return some(f.val)
  none(YNode)

proc yStr*(node: YNode, key: string): string =
  let v = node.yGet(key)
  if v.isSome and v.get.kind == yStr:
    v.get.strVal
  else:
    ""

proc yListStrs*(node: YNode, key: string): seq[string] =
  let v = node.yGet(key)
  if v.isNone or v.get.kind != yList:
    return @[]
  for it in v.get.items:
    if it.kind == yStr:
      result.add(it.strVal)

proc yListMaps*(node: YNode, key: string): seq[YNode] =
  let v = node.yGet(key)
  if v.isNone or v.get.kind != yList:
    return @[]
  for it in v.get.items:
    if it.kind == yMap:
      result.add(it)

proc yHasDuplicateKeys*(node: YNode): seq[string] =
  ## Report duplicate keys in any mapping reachable from `node` — a policy
  ## file with duplicate keys is ambiguous and must fail closed.
  case node.kind
  of yStr:
    discard
  of yList:
    for it in node.items:
      result.add(yHasDuplicateKeys(it))
  of yMap:
    var seen: seq[string] = @[]
    for f in node.fields:
      if f.key in seen:
        result.add(f.key)
      else:
        seen.add(f.key)
      result.add(yHasDuplicateKeys(f.val))
