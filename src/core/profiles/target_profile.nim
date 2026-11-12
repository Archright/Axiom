import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

import std/options
import core/integrity/integrity_refinement_types

## Abstract target profile for integrity refinement loop.
## Domain-specific profiles (Bitcoin, Nim, etc.) override these methods.

method selectRelevantOpcodeBlock*(
  profile: TargetProfile;
  violation: IntegrityViolationKind
): Option[OpcodeBlockProfile] {.base, inline, raises: [].} =
  none(OpcodeBlockProfile)

method buildQueryTag*(
  profile: TargetProfile;
  action: string;
  propertyName: string;
  opcodeBlock: Option[OpcodeBlockProfile]
): string {.base, inline, raises: [].} =
  profile.sourcePath & "#" & profile.sourceFingerprint & "/" & action & "/" & propertyName

method buildQueryText*(
  profile: TargetProfile;
  registry: InvariantRegistry;
  config: Z3WrapperConfig;
  violatedProperty: string;
  opcodeBlock: Option[OpcodeBlockProfile]
): string {.base, inline, raises: [].} =
  "(set-option :fixed_seed " & $config.fixedSeed & ")\n" &
    "(set-option :smt.threads 1)\n" &
    "; tag=" & config.queryTag & "\n" &
    "; property=" & violatedProperty & "\n" &
    "; source_path=" & profile.sourcePath & "\n" &
    "; source_fingerprint=" & profile.sourceFingerprint & "\n" &
    "(declare-const size Int)\n" &
    "(declare-const valid_top Bool)\n" &
    "(declare-const index Int)\n" &
    "(declare-const observed Int)\n" &
    "(check-sat)\n(get-model)\n(get-unsat-core)"

method hasStackSignals*(profile: TargetProfile): bool {.base, inline, raises: [].} = false
method hasTopSignals*(profile: TargetProfile): bool {.base, inline, raises: [].} = false
method hasBoundSignals*(profile: TargetProfile): bool {.base, inline, raises: [].} = false
method profileLabel*(profile: TargetProfile): string {.base, inline, raises: [].} = "generic"

{.pop.}
{.pop.}
