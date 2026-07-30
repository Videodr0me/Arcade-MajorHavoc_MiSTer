# Changelog

All notable changes to this project will be documented in this file.

## Initial Release [20260730]

### Features

- **Hardware-Level Major Havoc Core**: Reconstructs the original dual-processor
  arcade hardware from Atari's schematics and program sources, including its
  memory maps, interrupts, communication, vector-memory arbitration, and
  EEPROM.
- **PROM-Driven Vector Generator**: Implements the Atari Analog Vector
  Generator using the original state PROM, vector RAM and ROM, and four-bit
  Major Havoc color path.
- **Ultra High Performance Renderer**: High-resolution vector output at 240p,
  480p, 720p, and 1080p (recommended), with optional 120Hz output at 720p.
- **CRT Effects Pipeline**: Bloom, broad halo with independent strength, curve,
  spread, and compression controls, tone mapping, color processing, dot
  scaling, and an orientation-aware slot mask.
- **Phosphor Decay**: Models decay within a vector frame using each pixel's
  recorded draw time, plus phosphor persistence extending across frames.
- **Video Profiles**: Five resolution-aware presets and two independent custom
  slots expose the complete advanced effects controls.
- **Geometry and Zoom Controls**: Eight rotation and mirroring orientations
  with Near/Far framing.
- **Direct Video**: Explicit 15 kHz (240p) and 31 kHz (480p) output.
- **Roller Controls**: Roller, spinner, mouse, analog-stick, and digital
  left/right support with direction and sensitivity settings.
- **POKEY Accuracy**: Improved polynomial sequencing, channel timing, linked
  counters, high-pass behavior, and nonlinear output DAC. Passes the Tempest
  POKEY protection check.
- **Cabinet Audio**: Selectable recording-matched equal-gain and schematic
  2.2:1 mixes, plus a measured cabinet filter.
- **EEPROM and High Scores**: Persistent loading with optional automatic or
  manual saving of the original EEPROM data and the three stored high-score
  entries.
- **Integration**: Complete MRA configuration for ROMs, controls, coin
  inputs, gameplay DIP switches, Service Mode, auxiliary coin/diagnostic step,
  and EEPROM persistence.
