## Telemetry Layer Bridge — Thin Interface for tools/
## Re-exports gate telemetry health assessment types.
import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}
import core/telemetry/gate_telemetry
export gate_telemetry.GateHealth, gate_telemetry.GateHealthReport
export gate_telemetry.assessHealth, gate_telemetry.readJsonFile
export gate_telemetry.ghCritical, gate_telemetry.ghDegraded
{.pop.}