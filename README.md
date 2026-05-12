# Cache

Parameterized Cache IP PPA Exploration Project

## Overview

The purpose of this project is to design a parameterizable cache IP in SystemVerilog and explore PPA (Performance, Power, and Area) tradeoffs across different architectural configurations.

This project is written using ASIC-oriented RTL design practices while using FPGA implementation flows for rapid architectural exploration and timing analysis.

The cache architecture is designed to support configurable:
- Cache sizes
- Associativity
- Read latency
- Line size
- Memory organization

The goal of this project is not only functional correctness, but also high-frequency timing closure, scalable architecture exploration, and structural RTL optimization.

---

## Project Goals

- Develop reusable and technology-agnostic cache RTL
- Explore architectural PPA tradeoffs
- Analyze timing scalability across cache configurations
- Study the impact of associativity and cache size on timing and area
- Practice ASIC-oriented RTL development methodologies
- Build a clean and well-documented cache IP architecture

---

## Features

- Parameterizable cache architecture
- Configurable associativity
    - Direct-mapped
    - 2-way
    - 4-way
    - 8-way
- Configurable cache sizes
- Adjustable read latency
- Structural SystemVerilog RTL
- Technology-independent module organization
- FPGA-based timing and PPA exploration flow
- Modular cache subsystem design

---

## Planned Architecture

The cache design is planned to include:
- Address decode logic
- Tag array
- Data array
- Valid/dirty tracking
- Hit/miss detection
- Replacement policy logic
- Memory refill path
- CPU interface
- Downstream memory interface

---

## Verification

Verification will include:
- Directed testing
- Randomized testing
- Functional coverage
- Timing validation
- Corner-case testing

Simulation tools:
- Questa
- ModelSim

---

## PPA Exploration

The project will analyze:
- Fmax scaling
- Resource utilization
- Power consumption
- Associativity tradeoffs
- Cache size scaling
- Latency tradeoffs

Implementation sweeps will be performed across multiple parameter combinations using Vivado out-of-context synthesis and implementation flows.

---

## Tools Used

- SystemVerilog
- Vivado
- Questa / ModelSim
- TCL scripting
- Python scripting

---

## Future Work

- AXI interface support
- Non-blocking cache support
- Multi-level cache hierarchy
- Cache coherence experiments
- ASIC synthesis flow integration
- RTL-to-GDS exploration

---

## Repository Structure

```text
rtl/        -> RTL source files
tb/         -> Testbenches
scripts/    -> TCL and automation scripts
reports/    -> Timing, power, and utilization reports
docs/       -> Project documentation