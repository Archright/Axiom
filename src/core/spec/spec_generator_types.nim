import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Spec Generator Types
## Type definitions shared across spec_generator sub-modules.
## Extracted from spec_generator.nim to enable proper import-based module structure.

type
  NimSourceUnit* = object
    modulePath*: string
    source*: string

  LeanAliasDef* = object
    name*: string
    genericParams*: seq[string]
    targetType*: string

  LeanField* = object
    name*: string
    leanType*: string

  LeanStructureDef* = object
    name*: string
    genericParams*: seq[string]
    fields*: seq[LeanField]

  LeanParam* = object
    name*: string
    leanType*: string

  LeanFunctionDef* = object
    name*: string
    genericParams*: seq[string]
    params*: seq[LeanParam]
    returnType*: string
    trusted*: bool
    warnings*: seq[string]

  LeanEnumDef* = object
    name*: string
    genericParams*: seq[string]
    cases*: seq[string]

  SpecGeneratorOutput* = object
    leanCode*: string
    structureCount*: int
    enumCount*: int
    functionCount*: int
    untrustedFunctionCount*: int
    warnings*: seq[string]

  TypeMappingCertificate* = object
    nimType*: string
    leanType*: string
    smtSort*: string
    mappingProofObligation*: string
    verified*: bool
    sourceHash*: string

{.pop.}
