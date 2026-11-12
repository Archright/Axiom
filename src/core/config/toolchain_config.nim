import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Toolchain Configuration SSOT (WS-P2-B)
## Declaration-only constants — discovery-free. All build-time Z3 version
## checks (hermetic_build Startup Guard, build_metadata_generator) MUST import
## this module instead of re-declaring the version string.

const ExpectedZ3Version* = "4.13.3"  ## Declared Z3 semver the toolchain must match

{.pop.}
