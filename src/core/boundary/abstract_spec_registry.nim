import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import core/boundary/abstract_spec_lowering
import core/boundary/axiom_registry_loader
import core/types/results
import std/options
import std/strutils
type
  TypeTierInfo* = object
    typeName*: string
    tier*: LoweringTier
    axiomCount*: int
    registered*: bool

  AbstractSpecRegistry* = object
    typeMap*: seq[TypeTierInfo]
    axiomRegistry*: AxiomRegistry
# ── Registry Construction ──

func initAbstractSpecRegistry*(): AbstractSpecRegistry {.raises: [].} =
  ## Create an empty abstract spec registry.
  AbstractSpecRegistry(typeMap: @[])
func isRegistered*(registry: AbstractSpecRegistry;
                   nimType: string): bool {.raises: [].} =
  ## Check if a type has an explicit registry entry.
  let canon = nimType.strip().toLowerAscii()
  for entry in registry.typeMap:
    if entry.typeName.toLowerAscii() == canon:
      return true
  false
func registerType*(registry: var AbstractSpecRegistry; typeName: string;
                   tier: LoweringTier) {.raises: [].} =
  ## Register a type with explicit tier classification.
  let canon = typeName.strip()
  # Update if already exists
  for i, entry in registry.typeMap:
    if entry.typeName.toLowerAscii() == canon.toLowerAscii():
      registry.typeMap[i].tier = tier
      registry.typeMap[i].registered = true
      return
  registry.typeMap.add(TypeTierInfo(
    typeName: canon,
    tier: tier,
    axiomCount: 0,
    registered: true
  ))
func lowerTypeViaRegistry*(registry: AbstractSpecRegistry;
                           nimType: string): Result[LoweringResult, string] {.raises: [].} =
  ## Lower a Nim type using the registry for axiom lookup.
  lowerType(nimType, registry.axiomRegistry)
func lowerAllRegistered*(registry: AbstractSpecRegistry): seq[LoweringResult] {.raises: [].} =
  ## Lower all registered types, producing SMT-LIB2 fragments for each.
  result = @[]
  for entry in registry.typeMap:
    let lr = lowerTypeViaRegistry(registry, entry.typeName)
    if lr.isOk():
      result.add(lr.get)
func emitRegistrySmtLib2*(registry: AbstractSpecRegistry): string {.raises: [].} =
  ## Emit a complete SMT-LIB2 script for all registered types.
  let results = lowerAllRegistered(registry)
  emitSmtLib2(results)
func getTypeInfo*(registry: AbstractSpecRegistry;
                  nimType: string): Option[TypeTierInfo] {.raises: [].} =
  ## Look up tier info for a type. Returns none if not registered.
  let canon = nimType.strip().toLowerAscii()
  for entry in registry.typeMap:
    if entry.typeName.toLowerAscii() == canon:
      return some(entry)
  none(TypeTierInfo)
func registeredTypeCount*(registry: AbstractSpecRegistry): int {.raises: [].} =
  registry.typeMap.len

{.pop.}
