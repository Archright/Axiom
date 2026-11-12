import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

## Canonical architecture policy parser.
##
## The parser intentionally accepts only the deterministic lock-file grammar used
## by src/gate/architecture_policy.lock. It is not a general TOML parser.
##
## Implementation is split into importable sub-modules:
##   - architecture_policy_types:   type definitions + constants
##   - architecture_policy_part1:   helper parsing functions
##   - architecture_policy_part2:   main parse/load entry points + query funcs

import core/policy/architecture_policy_types
export architecture_policy_types
import core/policy/architecture_policy_part1
export architecture_policy_part1
import core/policy/architecture_policy_part2
export architecture_policy_part2

{.pop.}
