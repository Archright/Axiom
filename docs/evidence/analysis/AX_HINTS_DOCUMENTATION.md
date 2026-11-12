# TotalMemoryUsage Function Hints Documentation

## Overview

This document explains the Axiom hints created for the `TotalMemoryUsage()` functions in `bitcoin/src/txgraph.cpp`. These hints ensure compliance with the Zero-Vacuity Protocol by establishing meaningful invariants for memory usage calculations.

## Functions Analyzed

### 1. `GenericClusterImpl::TotalMemoryUsage() const noexcept`
- **Location**: `bitcoin/src/txgraph.cpp:915-925`
- **Implementation**:
  ```cpp
  return memusage::DynamicUsage(m_mapping) + 
         memusage::DynamicUsage(m_linearization) + 
         m_depgraph.DynamicMemoryUsage() + 
         memusage::MallocUsage(sizeof(GenericClusterImpl)) + 
         sizeof(std::unique_ptr<Cluster>);
  ```
- **Purpose**: Calculates total memory usage for a generic cluster implementation that supports multiple transactions
- **Complexity**: O(n) where n is the number of transactions in the cluster

### 2. `SingletonClusterImpl::TotalMemoryUsage() const noexcept`
- **Location**: `bitcoin/src/txgraph.cpp:927-933`
- **Implementation**:
  ```cpp
  return memusage::MallocUsage(sizeof(SingletonClusterImpl)) + 
         sizeof(std::unique_ptr<Cluster>);
  ```
- **Purpose**: Calculates total memory usage for a singleton cluster (single transaction)
- **Complexity**: O(1)

## Invariants Established

### Conservative Lower Bounds
These represent the minimum possible memory usage:

1. **GenericClusterImpl**: `sizeof(std::unique_ptr<Cluster>) + sizeof(GenericClusterImpl)`
   - Accounts for the object itself plus the unique_ptr wrapper
   - Even with no transactions, this is the minimum overhead

2. **SingletonClusterImpl**: `sizeof(std::unique_ptr<Cluster>) + sizeof(SingletonClusterImpl)`
   - Accounts for the smaller singleton object plus unique_ptr wrapper
   - Represents the absolute minimum memory usage

### Semantic Constraints
These enforce logical relationships:

1. **Minimum Dynamic Allocation**: GenericClusterImpl should return more than just the object size
   - Reflects the additional dynamic allocations for vectors and depgraph
   
2. **Alignment Requirements**: Both functions should return values aligned to pointer size
   - Ensures memory usage values are properly aligned

## Zero-Vacuity Protocol Compliance

The hints are designed to be:
- **Meaningful**: Not trivially true (e.g., not just `x >= 0`)
- **Useful**: Provide actual bounds on memory usage
- **Conservative**: Lower bounds will always be satisfied
- **Non-vacuous**: Upper bounds are loose enough to not be trivially false

## SMT Constraints

The constraints ensure:
1. Return values are never smaller than the object plus wrapper overhead
2. Generic clusters account for additional dynamic memory usage
3. Values are properly aligned for memory allocation
4. Upper bounds are generous enough to accommodate variations

## Usage in Axiom

These hints will be used by Axiom's verification system to:
1. Validate that memory usage calculations are within expected bounds
2. Detect potential memory leaks or incorrect calculations
3. Ensure consistency across different cluster implementations
4. Provide formal guarantees about memory usage semantics

## Testing Recommendations

When testing these functions:
1. Verify that empty clusters return at least the minimum size
2. Test with single-transaction clusters to validate singleton behavior
3. Check that memory usage scales appropriately with cluster size
4. Validate alignment properties for all return values