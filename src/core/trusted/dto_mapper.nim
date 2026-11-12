import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## DTO Mapper — automatic field mapping between internal types and DTOs.
##
## Used by contract modules (src/core/contracts/) to convert internal types
## to DTOs without manual boilerplate. Both templates compile to zero-cost
## inline code — no runtime allocation or indirection.
##
## Constraints:
##   - Source and DtoType must be `object` types (not `ref object`).
##   - Fields are matched by name AND type at compile time.
##   - Unmatched fields retain the DtoType's default (zero) values.

template mapDto*(DtoType: typedesc, source: untyped): DtoType =
  ## Auto-map matching fields from `source` to a new DtoType instance.
  ## Fields with the same name AND same type are copied automatically.
  ## Fields with different names or types are left at their default values
  ## and must be mapped manually or via `mapDtoWith`.
  ##
  ## Usage:
  ##   result = mapDto(TopologySummary, engineResult)
  var dto: DtoType
  for dstField, dstVal in fieldPairs(dto):
    for srcField, srcVal in fieldPairs(source):
      when dstField == srcField and typeof(dstVal) is typeof(srcVal):
        dstVal = srcVal
  dto

template mapDtoWith*(DtoType: typedesc, source: untyped,
                     overrides: untyped): DtoType =
  ## Like `mapDto`, but with manual field overrides for renamed fields
  ## or computed values that differ between source and destination types.
  ##
  ## The `overrides` block executes after auto-mapping, so it can both
  ## assign new values and reference the already-mapped fields.
  ##
  ## Usage:
  ##   result = mapDtoWith(TopologySummary, engineResult):
  ##     nodeId = engineResult.id
  ##     status = mapStatus(engineResult.state)
  var dto = mapDto(DtoType, source)
  overrides
  dto

{.pop.}
{.pop.}
