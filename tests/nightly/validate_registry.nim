## Step Definition Registry Validator
## Validates step_definitions.json integrity at build time (Fail-fast).
## Run: nim c -r tests/validate_registry.nim

import std/[json, os]

const
  RegistryPath = "tests/step_definitions.json"
  RequiredFields = ["func", "params", "module", "description"]

proc validate() =
  if not fileExists(RegistryPath):
    echo "ERROR: step_definitions.json not found at: ", RegistryPath
    quit(1)
  
  let content = readFile(RegistryPath)
  var registry: JsonNode
  try:
    registry = parseJson(content)
  except JsonParsingError as e:
    echo "ERROR: Invalid JSON in step_definitions.json: ", e.msg
    quit(1)
  
  # Check version
  if "version" notin registry:
    echo "ERROR: Missing 'version' field"
    quit(1)
  
  # Check steps
  if "steps" notin registry:
    echo "ERROR: Missing 'steps' field"
    quit(1)
  
  let steps = registry["steps"]
  var errors: seq[string] = @[]
  
  for stepName, stepDef in steps:
    # Check required fields
    for field in RequiredFields:
      if field notin stepDef:
        errors.add("Step '" & stepName & "': missing field '" & field & "'")
    
    # Check params is array
    if "params" in stepDef and stepDef["params"].kind != JArray:
      errors.add("Step '" & stepName & "': 'params' must be an array")
  
  if errors.len > 0:
    echo "ERROR: step_definitions.json validation failed:"
    for err in errors:
      echo "  - ", err
    quit(1)
  
  echo "PASS: step_definitions.json validated (", steps.len, " steps, version ", registry["version"].getStr(), ")"

validate()
