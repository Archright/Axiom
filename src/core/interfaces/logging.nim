## Hub Module forwarding stub — routes through logging_hub (IoC) and logging_facade (SSOT).
## See AGENTS.md §1.3a — Hub Module pattern.
import core/trusted/layer_declaration
axiomLayer "domain"
import core/interfaces/logging_hub
import infrastructure/logging_facade
export logging_hub, logging_facade
