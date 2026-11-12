import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/schema/schema_utils_macro
import core/schema/schema_utils_runtime
import core/schema/schema_utils_types
import std/[macros, json, sets]
export schema_utils_types
export schema_utils_macro
export schema_utils_runtime
export schema_utils_types
export schema_utils_macro
export schema_utils_runtime
# ---------------------------------------------------------------------------
# String conversions
# ---------------------------------------------------------------------------

# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func `$`*(v: ViolationSeverity): string {.inline, raises: [].} =
  case v
  of vsError: "error"
  of vsWarning: "warning"
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
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
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
# Compile-Time NimNode → PolicySchema Extraction
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
  else: pfkString  # fallback — validation will catch type mismatches
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
      # The fields argument — @[mkField(...), ...] or @[...]
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
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validateStringField*(json: JsonNode; field: PolicyFieldSpec;
    schemaName: string; basePath: string;
    violations: var seq[SchemaViolation]) =
  ## Validate a string field in a JsonNode at runtime.
  let fpath = if basePath.len > 0: basePath & "." & field.name
              else: field.name

  if not json.hasKey(field.name):
    if field.required:
      violations.add(SchemaViolation(
        severity: vsError, schemaName: schemaName,
        fieldPath: fpath, message: "required field missing"))
    return

  let val = json{field.name}
  if val.kind != JString:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected string, got " & $val.kind))
    return

  let s = val.getStr
  if field.required and s.len == 0:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath, message: "required field is empty"))
  if field.minLength > 0 and s.len < field.minLength:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "length " & $s.len & " < minimum " & $field.minLength))
  if field.maxLength > 0 and s.len > field.maxLength:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "length " & $s.len & " > maximum " & $field.maxLength))
  if field.allowedValues.len > 0 and s notin field.allowedValues:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "value '" & s & "' not in allowed set"))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validateIntField*(json: JsonNode; field: PolicyFieldSpec;
    schemaName: string; basePath: string;
    violations: var seq[SchemaViolation]) =
  ## Validate an int field in a JsonNode at runtime.
  let fpath = if basePath.len > 0: basePath & "." & field.name
              else: field.name

  if not json.hasKey(field.name):
    if field.required:
      violations.add(SchemaViolation(
        severity: vsError, schemaName: schemaName,
        fieldPath: fpath, message: "required field missing"))
    return

  let val = json{field.name}
  if val.kind != JInt:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected int, got " & $val.kind))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validateFloatField*(json: JsonNode; field: PolicyFieldSpec;
    schemaName: string; basePath: string;
    violations: var seq[SchemaViolation]) =
  ## Validate a float field in a JsonNode at runtime.
  let fpath = if basePath.len > 0: basePath & "." & field.name
              else: field.name

  if not json.hasKey(field.name):
    if field.required:
      violations.add(SchemaViolation(
        severity: vsError, schemaName: schemaName,
        fieldPath: fpath, message: "required field missing"))
    return

  let val = json{field.name}
  if val.kind notin {JFloat, JInt}:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected float, got " & $val.kind))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validateBoolField*(json: JsonNode; field: PolicyFieldSpec;
    schemaName: string; basePath: string;
    violations: var seq[SchemaViolation]) =
  ## Validate a bool field in a JsonNode at runtime.
  let fpath = if basePath.len > 0: basePath & "." & field.name
              else: field.name

  if not json.hasKey(field.name):
    if field.required:
      violations.add(SchemaViolation(
        severity: vsError, schemaName: schemaName,
        fieldPath: fpath, message: "required field missing"))
    return

  let val = json{field.name}
  if val.kind != JBool:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected bool, got " & $val.kind))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validateArrayField*(json: JsonNode; field: PolicyFieldSpec;
    schemaName: string; basePath: string;
    violations: var seq[SchemaViolation]) =
  ## Validate an array field in a JsonNode at runtime.
  let fpath = if basePath.len > 0: basePath & "." & field.name
              else: field.name

  if not json.hasKey(field.name):
    if field.required:
      violations.add(SchemaViolation(
        severity: vsError, schemaName: schemaName,
        fieldPath: fpath, message: "required field missing"))
    return

  let val = json{field.name}
  if val.kind != JArray:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected array, got " & $val.kind))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validateObjectField*(json: JsonNode; field: PolicyFieldSpec;
    schemaName: string; basePath: string;
    violations: var seq[SchemaViolation]) =
  ## Validate an object field in a JsonNode at runtime.
  let fpath = if basePath.len > 0: basePath & "." & field.name
              else: field.name

  if not json.hasKey(field.name):
    if field.required:
      violations.add(SchemaViolation(
        severity: vsError, schemaName: schemaName,
        fieldPath: fpath, message: "required field missing"))
    return

  let val = json{field.name}
  if val.kind != JObject:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected object, got " & $val.kind))
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validatePolicyConfig*(config: JsonNode;
    schema: PolicySchema): seq[SchemaViolation] =
  ## Validate a JsonNode policy config against a PolicySchema at runtime.
  ##
  ## Returns all violations found. An empty seq means the config is valid.
  ## Each violation includes the schema name, field path, message, and
  ## severity (error or warning).
  result = @[]

  for field in schema.fields:
    case field.kind
    of pfkString:
      validateStringField(config, field, schema.name, "", result)
    of pfkInt:
      validateIntField(config, field, schema.name, "", result)
    of pfkFloat:
      validateFloatField(config, field, schema.name, "", result)
    of pfkBool:
      validateBoolField(config, field, schema.name, "", result)
    of pfkArray:
      validateArrayField(config, field, schema.name, "", result)
    of pfkObject:
      validateObjectField(config, field, schema.name, "", result)

# ---------------------------------------------------------------------------
# Runtime Validation: validateAll
# ---------------------------------------------------------------------------
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func validateAll*(validators: openArray[SchemaValidator]): seq[SchemaViolation] =
  ## Run all schema validators and collect all violations.
  ##
  ## This is the primary runtime entry point for multi-schema validation.
  ## It aggregates violations from all validators into a single sequence.
  result = @[]

  for v in validators:
    let violations = validatePolicyConfig(v.config, v.schema)
    for violation in violations:
      var sv = violation
      if v.label.len > 0 and sv.schemaName.len == 0:
        sv.schemaName = v.label
      result.add(sv)
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func mkField*(name: string; kind: PolicyFieldKind; required = true;
    minLength = 0; maxLength = 0;
    allowedValues: seq[string] = @[]): PolicyFieldSpec {.raises: [].} =
  ## Convenience constructor for PolicyFieldSpec.
  PolicyFieldSpec(
    name: name,
    kind: kind,
    required: required,
    minLength: minLength,
    maxLength: maxLength,
    allowedValues: allowedValues
  )
# @axiom-hint: smt="vacuous_primitive"  # axiom:certified-exempt(import-heuristic; annotate-then-purge DEBT#303)
func mkSchema*(name: string; version: string;
    fields: seq[PolicyFieldSpec]): PolicySchema {.raises: [].} =
  ## Convenience constructor for PolicySchema.
  PolicySchema(name: name, version: version, fields: fields)

{.pop.}

