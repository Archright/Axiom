## Schema-as-Code Utilities -- Runtime Validation
##
## Runtime policy config validation returning structured violations.
## Validators access JsonNode which can raise CatchableError.

import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [CatchableError].}

import std/json
import core/schema/schema_utils_types

# ---------------------------------------------------------------------------
# Runtime Field Validators
# ---------------------------------------------------------------------------

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

  let val = json[field.name]
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

  let val = json[field.name]
  if val.kind != JInt:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected int, got " & $val.kind))

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

  let val = json[field.name]
  if val.kind notin {JFloat, JInt}:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected float, got " & $val.kind))

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

  let val = json[field.name]
  if val.kind != JBool:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected bool, got " & $val.kind))

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

  let val = json[field.name]
  if val.kind != JArray:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected array, got " & $val.kind))

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

  let val = json[field.name]
  if val.kind != JObject:
    violations.add(SchemaViolation(
      severity: vsError, schemaName: schemaName,
      fieldPath: fpath,
      message: "expected object, got " & $val.kind))

# ---------------------------------------------------------------------------
# Runtime Validation: validatePolicyConfig
# ---------------------------------------------------------------------------

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

type
  SchemaValidator* = object
    ## Pairs a schema with a config for batch validation.
    schema*: PolicySchema
    config*: JsonNode
    label*: string        ## Optional label for diagnostic messages.

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

func validateAll*(configs: openArray[JsonNode];
    schemas: openArray[PolicySchema]): seq[SchemaViolation] =
  ## Convenience overload: validates each config against the
  ## corresponding schema by index. If schemas has fewer entries
  ## than configs, extra configs are validated against the last schema.
  result = @[]

  let schemaCount = schemas.len
  if schemaCount == 0:
    return

  for i, config in configs:
    let schemaIdx = min(i, schemaCount - 1)
    let violations = validatePolicyConfig(config, schemas[schemaIdx])
    for v in violations:
      result.add(v)

{.pop.}
