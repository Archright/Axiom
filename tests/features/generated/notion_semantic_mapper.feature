@generated @medium
Feature: notion_semantic_mapper
  # generated | src/ui/notion_semantic_mapper.nim | ui | medium

  Scenario: exported types compile correctly
    # pending
    Given the module "ui/notion_semantic_mapper" is loaded
    Then all exported types should be instantiable
