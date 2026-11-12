import core/trusted/layer_declaration
import core/trusted/verification_result_types
axiomLayer "domain"
{.push raises: [].}

type
  ChcModelResultKind* = enum
    cmBuilt
    cmNotEncodable

  ChcModelResult* = object
    case kind*: ChcModelResultKind
    of cmBuilt:
      prelude*: string
      stateRel*: string
      initRule*: string
      transRule*: string
      stateVars*: string
      condSmt*: string
      declVars*: seq[string]
      sortStrs*: seq[string]
      loopVars*: seq[string]
    of cmNotEncodable:
      notEncodableReason*: string

  ChcPropertyResultKind* = enum
    cpBuilt
    cpNoProperty

  ChcPropertyResult* = object
    case kind*: ChcPropertyResultKind
    of cpBuilt:
      propertyRule*: string
      queryCmd*: string
      postDeclarations*: string
    of cpNoProperty:
      discard

{.pop.}