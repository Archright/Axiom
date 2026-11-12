import std/unittest
import gate/tag_parser

suite "tag_parser":
  test "empty content returns empty tags":
    let tags = parseFeatureTags("")
    check tags.tags.len == 0
    check not tags.isManual()

  test "untagged feature returns empty tags":
    let content = """
Feature: simple feature
  Scenario: something
    Given a step
"""
    let tags = parseFeatureTags(content)
    check tags.tags.len == 0
    check not tags.isManual()

  test "parses single tag before Feature":
    let content = """
@manual
Feature: manual audit process
  Scenario: something
"""
    let tags = parseFeatureTags(content)
    check tags.tags.len == 1
    check tags.tags[0] == "manual"
    check tags.isManual()

  test "parses multiple tags on one line":
    let content = """
@cli @invisible-observability
Feature: certificate solverMeta persistence
  Scenario: something
"""
    let tags = parseFeatureTags(content)
    check tags.tags.len == 2
    check tags.tags[0] == "cli"
    check tags.tags[1] == "invisible-observability"

  test "parses multiple tag lines":
    let content = """
@z3
@integrity
@stability
Feature: solver stability
  Scenario: something
"""
    let tags = parseFeatureTags(content)
    check tags.tags.len == 3
    check tags.tags[0] == "z3"
    check tags.tags[1] == "integrity"
    check tags.tags[2] == "stability"

  test "ignores tags after Feature keyword":
    let content = """
Feature: something
  @should-be-ignored
  Scenario: something
"""
    let tags = parseFeatureTags(content)
    check tags.tags.len == 0

  test "ignores content before tags":
    let content = """

@executable
Feature: something
"""
    let tags = parseFeatureTags(content)
    check tags.tags.len == 1
    check tags.tags[0] == "executable"
    check tags.isExecutable()

  test "isManual false for executable tag":
    let content = "@executable\nFeature: something"
    let tags = parseFeatureTags(content)
    check tags.isExecutable()
    check not tags.isManual()
