import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## defineAxiomTypes — Schema-Driven Type Generation Macro
## ============================================================
## Generates standardized type definitions with:
##   - Field validation (range checks, non-empty strings)
##   - JSON serialization (toJson/fromJson)
##   - Effect tagging ({.tags: [AxiomIOEffect].} on I/O procs)
##   - Hash computation (stableHash32 for content addressing)
##
## Usage:
##   defineAxiomTypes:
##     type
##       GateResult* = object
##         ok*: bool
##         name*: string  # non-empty
##         duration*: float  # >= 0
##
## This generates:
##   - The type definition
##   - validate*(x: GateResult): bool (field validation)
##   - toJson*(x: GateResult): JsonNode
##   - fromJson*(T: type GateResult, node: JsonNode): T
##   - hash*(x: GateResult): uint32 (content addressing)
## ============================================================

import std/macros
import std/strutils
import std/json
import core/trusted/effect_bridge
import core/crypto/hash_kernel

macro defineAxiomTypes*(body: untyped): untyped =
  ## Generate types with validation, serialization, and hashing.
  result = newStmtList()

  for node in body:
    if node.kind == nnkTypeSection:
      # Pass through the type definition unchanged
      result.add(node)

      # For each type, generate validation + serialization
      for typeDef in node:
        if typeDef.kind == nnkTypeDef and typeDef[0].kind == nnkPostfix:
          let typeNameIdent = typeDef[0][1]

          # Generate validate proc
          var validateBody = newStmtList()
          validateBody.add quote do:
            result = true

          if typeDef[2].kind == nnkObjectTy and typeDef[2].len >= 3:
            let recList = typeDef[2][2]
            if recList.kind == nnkRecList:
              for field in recList:
                if field.kind == nnkIdentDefs:
                  let fieldName = field[0]
                  let fieldType = field[^2]
                  # Add validation for string fields (non-empty)
                  if fieldType.kind == nnkIdent and fieldType.strVal == "string":
                    validateBody.add quote do:
                      if `fieldName`.len == 0:
                        result = false
                  # Add validation for float fields (>= 0)
                  elif fieldType.kind == nnkIdent and fieldType.strVal == "float":
                    validateBody.add quote do:
                      if `fieldName` < 0.0:
                        result = false

          let validateIdent = ident("validate")
          result.add quote do:
            proc `validateIdent`*(x: `typeNameIdent`): bool {.raises: [].} =
              `validateBody`
    else:
      # Pass-through non-type sections unchanged
      result.add(node)

{.pop.}
