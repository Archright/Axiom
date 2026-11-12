## Topology Manifest Bootstrap Generator — Pure manifest generation.
## AGENTS.md Topology Contract §Phase C
## Generates topology.json from pre-loaded declaration and file list.
## File I/O wrappers live in infrastructure/topology_executor.nim.

import core/trusted/layer_declaration
axiomLayer "domain"
import std/[json, strutils, tables, algorithm]
import core/topology/declaration
import core/topology/topology_types
{.push raises: [].}
# axiomIoBoundary

func ensureSubdomain*(domains: JsonNode; domain, subdomain, desc: string; pathHint: string) {.raises: [].} =
  var domainNode = domains{domain}
  if domainNode.isNil:
    domainNode = %*{
      "description": domain & " domain",
      "level": 1,
      "target_level": 1,
      "allowed_imports": [],
      "subdomains": {}
    }
    domains[domain] = domainNode
  var subdomains = domainNode{"subdomains"}
  if subdomains.isNil:
    subdomains = newJObject()
    domainNode["subdomains"] = subdomains
  if subdomains{subdomain}.isNil:
    var paths = newJArray()
    if pathHint.len > 0:
      paths.add(%pathHint)
    subdomains[subdomain] = %*{
      "description": if desc.len > 0: desc else: "Auto-generated from filesystem",
      "paths": paths
    }

func inferFromPath*(filePath: string): tuple[domain, subdomain: string] {.raises: [].} =
  ## Fallback heuristic: derive domain from top-level directory under src/.
  let parts = filePath.split('/')
  if parts.len >= 2 and parts[0] == "src":
    let domain = parts[1]
    var subdomain = if parts.len >= 3: parts[2] else: "root"
    subdomain = subdomain.replace(".nim", "")
    # Map common root files to a more meaningful subdomain
    if subdomain == topologyExtractFilename(filePath).replace(".nim", ""):
      subdomain = "root"
    return (domain, subdomain)
  return ("", "unmapped")

func determineMapping*(filePath: string; existingDecl: TopologyDeclaration): tuple[domain, subdomain: string] {.raises: [].} =
  ## Prefer existing declaration, then built-in patterns, then path inference.
  if existingDecl.domains.len > 0 or existingDecl.mappingByPattern.len > 0 or existingDecl.mappingByFile.len > 0:
    let (d, s, _) = classifyFile(filePath, existingDecl)
    if d.len > 0:
      return (d, s)

  # Built-in bootstrap patterns
  if filePath.startsWith("src/core/topology_"):
    return ("core", "topology")
  if filePath.startsWith("src/verification/proof_vault") or
     filePath.startsWith("src/verification/certificate"):
    return ("verification", "proof")
  if filePath.startsWith("src/verification/lean_lsp") or
     filePath.startsWith("src/verification/z3"):
    return ("verification", "bridges")
  if filePath.startsWith("src/verification/batch_uap") or
     filePath.startsWith("src/verification/uap"):
    return ("verification", "orchestration")
  if filePath.startsWith("src/verification/pipeline"):
    return ("verification", "pipeline")
  if filePath.startsWith("src/cli/commands/"):
    return ("cli", "commands")
  if filePath.startsWith("src/cli/wf_"):
    return ("cli", "workflow")
  if filePath.startsWith("src/cli/report_"):
    return ("cli", "report")
  if filePath.startsWith("src/cli/action_"):
    return ("cli", "actions")

  result = inferFromPath(filePath)

func generateManifestJsonFromData*(existingDecl: TopologyDeclaration;
                                   files: seq[string]): JsonNode {.raises: [].} =
  ## Pure: generate a topology manifest from pre-loaded declaration and file list.
  var domains = newJObject()

  # Ensure unmapped subdomain exists in every known domain
  let knownDomains = ["core", "verification", "cli", "gate", "personas", "api", "engine", "sieve", "semantic_proofs", "frontend", "mcp"]
  for dn in knownDomains:
    ensureSubdomain(domains, dn, "unmapped", "Pending human classification", "")

  # Merge existing declaration domains if present
  for dn, d in existingDecl.domains:
    var domainNode = domains{dn}
    if domainNode.isNil:
      domainNode = %*{
        "description": d.description,
        "level": d.level,
        "target_level": d.targetLevel,
        "allowed_imports": d.allowedImports,
        "subdomains": {}
      }
      domains[dn] = domainNode
    var subdomains = domainNode{"subdomains"}
    if subdomains.isNil:
      subdomains = newJObject()
      domainNode["subdomains"] = subdomains
    for sn, s in d.subdomains:
      if subdomains{sn}.isNil:
        var paths = newJArray()
        for p in s.paths:
          paths.add(%p)
        subdomains[sn] = %*{
          "description": s.description,
          "paths": paths
        }

  var byFile = newJObject()
  var byPattern = newJArray()

  # Preserve existing by_pattern declarations
  for p in existingDecl.mappingByPattern:
    byPattern.add(%*{
      "pattern": p.pattern,
      "domain": p.domain,
      "subdomain": p.subdomain
    })

  var sortedFiles = files
  algorithm.sort(sortedFiles)

  for relPath in sortedFiles:
    let (d, s) = determineMapping(relPath, existingDecl)
    var mapping = newJObject()
    mapping["domain"] = %d
    mapping["subdomain"] = %s
    byFile[relPath] = mapping
    if d.len > 0:
      let pathHint = topologyParentDir(relPath)
      ensureSubdomain(domains, d, s, "", pathHint)

  let root = newJObject()
  root["_schema"] = %"axiom-topology-declaration/v1"
  root["domains"] = domains
  var mapping = newJObject()
  mapping["by_pattern"] = byPattern
  mapping["by_file"] = byFile
  root["mapping"] = mapping
  result = root

func generateManifestJsonString*(existingDecl: TopologyDeclaration;
                                files: seq[string]): string {.raises: [].} =
  ## Pure: render topology manifest as JSON string.
  result = generateManifestJsonFromData(existingDecl, files).pretty

{.pop}
