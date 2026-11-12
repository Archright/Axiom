{.push raises: [].}
## Schema-as-Code Utilities — Compile-Time Macro Infrastructure
##
## Compile-time policy loading macro with detailed validation diagnostics.
## Validates `policyExpr` against a `PolicySchema` at compile time.
## On violation, emits a compiler error with line/column diagnostics.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/macros
import std/sets
import core/schema/schema_utils_types

# ---------------------------------------------------------------------------
# Compile-Time Validation Helpers
# ---------------------------------------------------------------------------

func validateFieldAtCompileTime(node: NimNode; field: PolicyFieldSpec;
    schemaName: string; violations: var seq[SchemaViolation]) =
  ## Validate a single field node against its spec at compile time.
  ##
  ## Appends violations with line/column from the source node.
  let li = node.lineInfoObj
  let line = li.line
  let col = li.column

  case field.kind
  of pfkString:
    if node.kind != nnkStrLit and node.kind != nnkRStrLit and
        node.kind != nnkTripleStrLit:
      violations.add(SchemaViolation(
        severity: vsError,
        schemaName: schemaName,
        fieldPath: field.name,
        message: "expected string, got " & $node.kind,
        line: line, column: col
      ))
    else:
      let s = node.strVal
      if field.required and s.len == 0:
        violations.add(SchemaViolation(
          severity: vsError,
          schemaName: schemaName,
          fieldPath: field.name,
          message: "required field is empty",
          line: line, column: col
        ))
      if field.minLength > 0 and s.len < field.minLength:
        violations.add(SchemaViolation(
          severity: vsError,
          schemaName: schemaName,
          fieldPath: field.name,
          message: "length " & $s.len & " < minimum " & $field.minLength,
          line: line, column: col
        ))
      if field.maxLength > 0 and s.len > field.maxLength:
        violations.add(SchemaViolation(
          severity: vsError,
          schemaName: schemaName,
          fieldPath: field.name,
          message: "length " & $s.len & " > maximum " & $field.maxLength,
          line: line, column: col
        ))
      if field.allowedValues.len > 0 and s notin field.allowedValues:
        violations.add(SchemaViolation(
          severity: vsError,
          schemaName: schemaName,
          fieldPath: field.name,
          message: "value '" & s & "' not in allowed set",
          line: line, column: col
        ))
  of pfkInt:
    if node.kind notin {nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit,
        nnkInt64Lit, nnkUIntLit, nnkUInt8Lit, nnkUInt16Lit, nnkUInt32Lit,
        nnkUInt64Lit}:
      violations.add(SchemaViolation(
        severity: vsError,
        schemaName: schemaName,
        fieldPath: field.name,
        message: "expected int, got " & $node.kind,
        line: line, column: col
      ))
  of pfkFloat:
    if node.kind notin {nnkFloatLit, nnkFloat32Lit, nnkFloat64Lit,
        nnkFloat128Lit} and not (node.kind in {nnkIntLit, nnkInt8Lit,
        nnkInt16Lit, nnkInt32Lit, nnkInt64Lit}):
      violations.add(SchemaViolation(
        severity: vsError,
        schemaName: schemaName,
        fieldPath: field.name,
        message: "expected float, got " & $node.kind,
        line: line, column: col
      ))
  of pfkBool:
    if node.kind != nnkIdent or node.strVal notin ["true", "false"]:
      violations.add(SchemaViolation(
        severity: vsError,
        schemaName: schemaName,
        fieldPath: field.name,
        message: "expected bool (true/false), got " & $node.kind,
        line: line, column: col
      ))
  of pfkArray:
    if node.kind != nnkBracket:
      violations.add(SchemaViolation(
        severity: vsError,
        schemaName: schemaName,
        fieldPath: field.name,
        message: "expected array [...], got " & $node.kind,
        line: line, column: col
      ))
  of pfkObject:
    if node.kind notin {nnkObjConstr, nnkPar}:
      violations.add(SchemaViolation(
        severity: vsError,
        schemaName: schemaName,
        fieldPath: field.name,
        message: "expected object, got " & $node.kind,
        line: line, column: col
      ))

func validateObjectFields(node: NimNode; schema: PolicySchema;
    basePath: string; violations: var seq[SchemaViolation]) =
  ## Walk an object-construction node and validate each field against the schema.
  let line = node.lineInfoObj.line
  let col = node.lineInfoObj.column

  # Collect present field names from the constructor
  # Handles nnkObjConstr (Type(field: val)), nnkTupleConstr ((field: val)),
  # and nnkPar ((field: val)).
  let isConstr = node.kind in {nnkObjConstr, nnkTupleConstr, nnkPar}
  var presentFields: HashSet[string]
  if isConstr:
    for child in node:
      if child.kind == nnkExprColonExpr and child.len >= 1:
        presentFields.incl(child[0].strVal)

  # Validate each spec field
  for field in schema.fields:
    let fpath = if basePath.len > 0: basePath & "." & field.name
                else: field.name
    if field.name in presentFields:
      # Find the corresponding child node
      if isConstr:
        for child in node:
          if child.kind == nnkExprColonExpr and child.len >= 2 and
              child[0].strVal == field.name:
            validateFieldAtCompileTime(child[1], field, schema.name,
                violations)
            break
    elif field.required:
      violations.add(SchemaViolation(
        severity: vsError,
        schemaName: schema.name,
        fieldPath: fpath,
        message: "required field missing",
        line: line, column: col
      ))

# ---------------------------------------------------------------------------
# Compile-Time NimNode -> PolicySchema Extraction
# ---------------------------------------------------------------------------

func extractFieldKind(node: NimNode): PolicyFieldKind {.compileTime.} =
  ## Extract a PolicyFieldKind enum value from a NimNode identifier.
  let name = node.strVal
  case name
  of "pfkString": pfkString
  of "pfkInt": pfkInt
  of "pfkFloat": pfkFloat
  of "pfkBool": pfkBool
  of "pfkArray": pfkArray
  of "pfkObject": pfkObject
  else: pfkString  # fallback -- validation will catch type mismatches

func extractStringSeq(node: NimNode): seq[string] {.compileTime.} =
  ## Extract a seq[string] from a NimNode bracket or @[] expression.
  result = @[]
  if node.kind == nnkPrefix and node.len >= 2:
    # @[...] syntax: nnkPrefix(nnkAt, nnkBracket, ...)
    let bracket = node[1]
    if bracket.kind == nnkBracket:
      for child in bracket:
        if child.kind in {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
          result.add(child.strVal)
  elif node.kind == nnkBracket:
    for child in node:
      if child.kind in {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
        result.add(child.strVal)

func extractPolicyFieldSpec(node: NimNode): PolicyFieldSpec {.compileTime.} =
  ## Extract a PolicyFieldSpec from a NimNode representing a mkField() call
  ## or a PolicyFieldSpec constructor.
  result = PolicyFieldSpec()

  # Handle mkField("name", pfkString, required = true, ...)
  if node.kind == nnkCall and node.len >= 1:
    let args = node
    # Positional: args[0] = mkField ident, args[1] = name, args[2] = kind
    if args.len >= 3:
      result.name = args[1].strVal
      result.kind = extractFieldKind(args[2])
    # Named params: args[3..] can be nnkExprEqExpr
    for i in 3..<args.len:
      let arg = args[i]
      if arg.kind == nnkExprEqExpr and arg.len >= 2:
        let key = arg[0].strVal
        let val = arg[1]
        case key
        of "required":
          result.required = (val.kind == nnkIdent and val.strVal == "true")
        of "minLength":
          if val.kind in {nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit,
              nnkInt64Lit}:
            result.minLength = val.intVal.int
        of "maxLength":
          if val.kind in {nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit,
              nnkInt64Lit}:
            result.maxLength = val.intVal.int
        of "allowedValues":
          result.allowedValues = extractStringSeq(val)
  # Handle PolicyFieldSpec(name: "x", kind: pfkString, ...) object constructor
  elif node.kind == nnkObjConstr:
    for child in node:
      if child.kind == nnkExprColonExpr and child.len >= 2:
        let key = child[0].strVal
        let val = child[1]
        case key
        of "name":
          result.name = val.strVal
        of "kind":
          result.kind = extractFieldKind(val)
        of "required":
          result.required = (val.kind == nnkIdent and val.strVal == "true")
        of "minLength":
          if val.kind in {nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit,
              nnkInt64Lit}:
            result.minLength = val.intVal.int
        of "maxLength":
          if val.kind in {nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit,
              nnkInt64Lit}:
            result.maxLength = val.intVal.int
        of "allowedValues":
          result.allowedValues = extractStringSeq(val)

func extractPolicySchema(node: NimNode): PolicySchema {.compileTime.} =
  ## Extract a PolicySchema from a NimNode representing a mkSchema() call
  ## or a PolicySchema object constructor.
  result = PolicySchema()

  if node.kind == nnkCall and node.len >= 1:
    # mkSchema("name", "version", @[...]) positional
    let args = node
    if args.len >= 3:
      result.name = args[1].strVal
      result.version = args[2].strVal
    if args.len >= 4:
      # The fields argument -- @[mkField(...), ...] or @[...]
      let fieldsNode = args[3]
      if fieldsNode.kind == nnkPrefix and fieldsNode.len >= 2:
        let bracket = fieldsNode[1]
        if bracket.kind == nnkBracket:
          for child in bracket:
            result.fields.add(extractPolicyFieldSpec(child))
      elif fieldsNode.kind == nnkBracket:
        for child in fieldsNode:
          result.fields.add(extractPolicyFieldSpec(child))
  elif node.kind == nnkObjConstr:
    for child in node:
      if child.kind == nnkExprColonExpr and child.len >= 2:
        let key = child[0].strVal
        let val = child[1]
        case key
        of "name": result.name = val.strVal
        of "version": result.version = val.strVal
        of "fields":
          if val.kind == nnkPrefix and val.len >= 2:
            let bracket = val[1]
            if bracket.kind == nnkBracket:
              for child in bracket:
                result.fields.add(extractPolicyFieldSpec(child))
          elif val.kind == nnkBracket:
            for child in val:
              result.fields.add(extractPolicyFieldSpec(child))

# ---------------------------------------------------------------------------
# Compile-Time Macro: loadPolicyTypes
# ---------------------------------------------------------------------------

macro loadPolicyTypes*(policyExpr: untyped; schema: untyped): untyped =
  ## Compile-time policy loading macro.
  ##
  ## Validates `policyExpr` against the given `PolicySchema` at compile time.
  ## On success, returns the expression unchanged (pass-through).
  ## On violation, emits a compiler error with line/column diagnostics.
  ##
  ## Usage:
  ##   const MyPolicy = loadPolicyTypes(@[...], mySchema)
  ##
  ## The macro inspects the AST of `policyExpr`, walks object constructors,
  ## and validates each field against the schema spec. Error messages include
  ## the source file line and column from `NimNode.lineInfoObj`.
  ##
  ## `schema` can be any expression that constructs a PolicySchema:
  ##   - mkSchema("name", "v1", @[mkField(...)])
  ##   - PolicySchema(name: "x", version: "v1", fields: @[...])
  ##   - A const variable reference (resolved at compile time)
  var violations: seq[SchemaViolation]

  # Extract the PolicySchema from the NimNode AST
  let extractedSchema = extractPolicySchema(schema)

  # Unwrap prefix/call nodes to get to the actual data structure.
  # @[...] -> nnkPrefix(nnkIdent("@"), nnkBracket)
  # @[]    -> nnkCall(nnkIdent("@"), nnkBracket)
  var expr = policyExpr
  while expr.kind == nnkPrefix and expr.len >= 2:
    expr = expr[1]
  while expr.kind == nnkCall and expr.len >= 2:
    expr = expr[1]

  # Handle both single object and seq of objects
  case expr.kind
  of nnkBracket:  # @[...] array literal
    for i, child in expr:
      if child.kind == nnkObjConstr:
        validateObjectFields(child, extractedSchema, "[" & $i & "]",
            violations)
      elif child.kind in {nnkPar, nnkTupleConstr}:
        # Tuple syntax -- validate fields present
        validateObjectFields(child, extractedSchema, "[" & $i & "]",
            violations)
      else:
        let li = child.lineInfoObj
        violations.add(SchemaViolation(
          severity: vsError,
          schemaName: extractedSchema.name,
          fieldPath: "[" & $i & "]",
          message: "expected object constructor, got " & $child.kind,
          line: li.line, column: li.column
        ))
  of nnkObjConstr:
    validateObjectFields(expr, extractedSchema, "", violations)
  of nnkPar, nnkTupleConstr:
    validateObjectFields(expr, extractedSchema, "", violations)
  else:
    let li = expr.lineInfoObj
    violations.add(SchemaViolation(
      severity: vsError,
      schemaName: extractedSchema.name,
      fieldPath: "",
      message: "unexpected expression kind: " & $expr.kind,
      line: li.line, column: li.column
    ))

  # Emit compiler errors for all violations
  if violations.len > 0:
    var errMsg = "SCHEMA VIOLATION (" & extractedSchema.name & " " &
        extractedSchema.version & "): " & $violations.len & " error(s)\n"
    for v in violations:
      errMsg.add("  " & $v & "\n")
    macros.error(errMsg)

  # Pass-through: return the original expression
  result = policyExpr
