import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary

# ── imported sub-modules ──
import core/translator/universal_mapper_part1
import core/translator/universal_mapper_part2
export universal_mapper_part1
export universal_mapper_part2

{.pop.}
