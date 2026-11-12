# SDK Implementation Templates

Minimal, working boilerplate for each Kimi-SDK interface.

## Usage

1. Copy the template for the interface you need
2. Search for `TODO` markers — these are your customization points
3. Run the test skeleton to verify your implementation compiles

## Templates

| Template | Interface | Use Case |
|----------|-----------|----------|
| `command_validator_minimal.nim` | `ICommandValidator` | Custom command validation gates |
| `audit_storage_minimal.nim` | `IAuditStorage` | Custom audit persistence backends |
| `gate_runner_minimal.nim` | `ICommandValidator` (simplified) | Quick gate prototypes |
| `evidence_store_minimal.nim` | `IEvidenceStore` | Custom evidence persistence |

## Rule

New gates/validators MUST start from these templates, not from scratch.
SDK interfaces must be implemented via the template pattern to maintain consistency.
