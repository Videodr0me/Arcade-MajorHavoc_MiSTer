# Major Havoc (Arcade, 1983) for MiSTer FPGA

An FPGA implementation of Atari's color vector arcade game **Major Havoc** for
the [MiSTer FPGA](https://github.com/MiSTer-devel/Main_MiSTer/wiki) platform.

Major Havoc combines roller-controlled space combat, maze exploration,
Breakout-style intermissions, and a vivid color vector display. This core
reconstructs the original dual-processor arcade hardware from Atari's
schematics and pairs it with a high-resolution vector renderer and CRT-effects
pipeline.

## Support the Project

Hey, Videodr0me here! If you enjoy reliving the golden age of arcade games,
please support my work and future updates:
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-support-yellow?style=flat-square&logo=buy-me-a-coffee)](https://buymeacoffee.com/Videodr0me)

---

## Original Hardware

| Subsystem | Original Hardware | FPGA Implementation |
|---|---|---|
| **Main Processors** | Alpha 6502 at 2.5 MHz and Gamma 6502 at 1.25 MHz, derived from a 10.000 MHz clock | Two T65 cpu modules with the original clock rates, memory maps, communication, interrupts, and vector-memory arbitration |
| **Vector Generator** | PROM-sequenced Atari Analog Vector Generator with its own 12.096 MHz clock, vector RAM/ROM, color RAM, DACs, and analog integrators | PROM-driven AVG using the original state PROM and four-bit Major Havoc color path |
| **Audio** | Four Atari POKEYs at 1.25 MHz with analog output mixing and filtering | Four improved POKEY implementations with selectable measured and schematic mixing plus a measured cabinet filter |
| **Display** | Horizontal color XY vector monitor | High-resolution raster vector renderer with bloom, halo, tone mapping, and intra-frame and inter-frame phosphor decay |
| **Controls** | Optical roller, Jump, and Shield buttons | Roller, spinner, mouse, analog-stick, and digital left/right support |
| **Non-volatile Memory** | 512-byte Atari 2804 parallel EEPROM | Persistent MiSTer NVRAM with manual and optional automatic saving |

---

## Controls

Major Havoc was designed around a free-spinning optical roller. A real roller
or spinner gives the most authentic gameplay, but the core also supports a
mouse, an analog stick, and digital left/right controls.

| Input | Function |
|---|---|
| **Roller / Spinner / Mouse** | Move Major Havoc left or right |
| **Analog Stick** | Proportional left/right roller emulation |
| **Digital Left / Right** | Digital roller emulation using a joystick, D-pad, or keyboard |
| **Jump / Fire / Start 1P (Button A)** | Jump, fire, or start a one-player game |
| **Shield / Start 2P (Button B)** | Activate the shield or start a two-player game |
| **Coin Left / Coin Right** | Operate the left or right coin mechanism |
| **Pause (Select)** | Pause or resume the game |

The **Input Controls** menu provides these adjustments:

| Option | Description |
|---|---|
| **Direction** | Reverses roller, spinner, mouse, analog-stick, and digital movement for alternate controller or cabinet wiring. |
| **Sensitivity** | Scales all roller input methods from 0.125x through 2.0x. |

For USB spinners, MiSTer's `spinner_throttle` setting can be used in addition
to the core's **Sensitivity** setting.

---

## Requirements

The CRT-style video pipeline uses MiSTer SDRAM and requires a 32MB SDRAM module
or larger. Use the included MRA so the program ROMs, original AVG state PROM,
controls, DIP switches, and EEPROM persistence are configured correctly.

---

## Recommended MiSTer Video Settings

The renderer supports 240p, 480p, 720p, and 1080p output. For the highest
vector detail, **1080p is recommended**. The game looks especially good on an
OLED display. Compatible 720p displays can use the optional 120Hz mode for
smoother frame presentation.

For high-resolution flat-panel output, add the following settings under the
exact `[Major Havoc]` header in `mister.ini`. MiSTer's scaler filters and
shadow mask are disabled so they do not alter the core's rendered image.

```ini
[Major Havoc]
video_mode=8              ; 8 = 1080p, or use 0 = 720p
vsync_adjust=2            ; Try 0 or 1 if your display has compatibility issues
vscale_mode=0             ; Let the core provide its optimized aspect ratio
hdmi_limited=0            ; Use 1 for displays expecting limited RGB range
hdr=0                     ; hdr = 1 is recommended when the display supports it
vrr_mode=0                ; Try 1 or higher if required for 120 Hz compatibility
vfilter_default=          ; Leave scaler filters blank
vfilter_vertical_default=
vfilter_scanlines_default=
shmask_default=
shmask_mode_default=0
```

The empty filter entries override filters inherited from the global
`[MiSTer]` section.

### Direct Video and CRT Output

When Direct Video is active, use **Direct Video Scan Rate** under
**Video Timing & Geometry** to select 15 kHz (240p) or 31 kHz (480p) output.

Without Direct Video, configure a CRT-compatible video mode in `mister.ini`.
For 15 kHz output, use an exact 640x240 mode:

```ini
[Major Havoc]
video_mode=640,240,60
vscale_mode=4
vsync_adjust=0
composite_sync=1
```

For 31 kHz output, use the corresponding 640x480 mode:

```ini
[Major Havoc]
video_mode=640,480,60
vscale_mode=4
vsync_adjust=0
composite_sync=1
```

These settings can also be placed in the applicable global section of
`mister.ini` instead of the dedicated `[Major Havoc]` section. Experiment with
`vscale_mode` and horizontal resolution to find the best results for your CRT.

When using a real CRT, start with **A Touch of CRT**, **Off**, or a **Custom**
profile. Stronger profiles recreate characteristics that the tube may already
provide, including bloom, halo, and phosphor persistence.

---

## OSD Options

### Video Profiles & Effects

| Option | Description |
|---|---|
| **Profile** | Selects five fixed video presets, two independently saved custom slots, or the effects-filter bypass path. |

#### Video Profiles

| Profile | Description |
|---|---|
| **Off** | Bypasses bloom and halo. Dot Scale, Tone Mapping, Color Space, Slot Mask, and both phosphor-decay controls remain available. |
| **A Touch of CRT** | Adds a subtle CRT halo and bloom. |
| **80s Cruise Control** | Adds richer halos, more bloom, and restrained inter-frame persistence. This is the default profile. |
| **80s Overdrive** | Models a heavily driven arcade CRT with stronger glow and phosphor persistence. |
| **Neon Fever Dream** | Stylized high-energy vector presentation with excessive flashing bright lights. |
| **Plasma Storm** | A deliberately impossible mix of fast-changing vectors and long glowing trails. |
| **Custom 1 / Custom 2** | Two independent user-configurable slots exposing the complete advanced effects controls. |

> **Warning:** Neon Fever Dream and Plasma Storm feature excessive flashing
> bright lights and should not be used by anyone sensitive to them.

#### Custom Profile Controls

Selecting **Custom 1** or **Custom 2** exposes the complete effects controls:

| Option | Description |
|---|---|
| **Dot Scale** | Selects 1x, 2x, 2.5x, or 3x rendering for vector dots and particle endpoints (unused by Major Havoc). |
| **Tone Mapping** | Selects how the original vector intensity is mapped to the digital output range. |
| **Bloom Width** | Controls the radius of local bloom around bright vector pixels. |
| **Bloom Curve** | Controls how readily increasing intensity produces bloom. |
| **Halo** | Sets the strength of the broad CRT halo. |
| **Halo Curve** | Controls how source brightness is translated into broad halo energy. |
| **Halo Spread** | Selects the spatial distribution of halo energy. |
| **Halo Compression** | Sets the energy threshold above which halo highlights are softly compressed. |
| **Inter-Frame Decay** | Retains decayed history from earlier vector frames. |
| **Intra-Frame Decay** | Uses each pixel's recorded draw phase to vary its brightness within a frame. |
| **Color Space** | Selects the original output or Amp709 color conversion. |
| **Color Effect** | Selects the original output, RGB channel permutations, weighted B/W, or Negative. |
| **Slot Mask** | Adds an orientation-aware adaptive slot-mask effect for high-resolution displays. |

Favor Inter-Frame Decay for long-persistence phosphors and high frame redraw
rates, or Intra-Frame Decay for faster phosphors and slower redraw rates.
Combine both for deliberately stylized effects.

Both Custom slots retain
their own settings through MiSTer's **Save Settings** command.

### Video Timing & Geometry

| Option | Description |
|---|---|
| **Orientation** | Provides all eight unique rotation and mirroring combinations. |
| **Zoom** | **Near** frames normal gameplay tightly. **Far** exposes more of the AVG drawing area. |
| **Buffer Mode** | Selects whether completed vector frames are presented at EOF, VBLANK, or the recommended EOF + VBLANK combination. |
| **120Hz (720p only)** | Enables approximately 120Hz output when the active mode is 720p. |
| **Direct Video Scan Rate** | Selects 15 kHz (240p) or 31 kHz (480p) while Direct Video is active. |
| **Aspect Ratio** | Keep **Optimized** selected. Change this only as a last resort when display settings cannot produce the correct picture shape. **Stretched** fills the display, while **Pixel Perfect** requests direct pixel mapping. |

### Cabinet Audio Hardware

| Option | Default | Description |
|---|---|---|
| **Audio Mixing** | Measured | Uses the measured gains for all four POKEYs. `Schematics` applies the documented 2.2:1 gain for POKEY 4. |
| **Cabinet Filter** | Measured | Applies the shared response measured from original cabinet recordings. `Off` provides the unfiltered POKEY mix. |

---

## High Scores and EEPROM/NVRAM

Major Havoc displays ten high-score entries. The original program saves only
the top three scores and their initials in its 512-byte EEPROM; the remaining
seven entries use the game's built-in defaults after a cold start.

To view the high-score table, enter attract mode and move the roller to the
left. Move it to the right to return to the normal attract sequence.

To restore the default high-score table:

1. Set **Service Mode** to **On** and wait 3-4 seconds for self-test to appear.
2. Use **Shield** to select **Reset High Scores**.
3. Hold **Coin Right**, then press and release **Jump**.
4. Wait for the loud hissing sound to finish.
5. Leave self-test running for at least another 10 seconds before setting
   **Service Mode** to **Off** or powering down.
6. Select **Save NVRAM** in the core menu so the reset EEPROM is also stored
   persistently on the MiSTer SD card.

MiSTer stores the EEPROM image under `/media/fat/config/nvram/` using the MRA
name.

- Enable **Autosave NVRAM** to save modified EEPROM data when the OSD is
  opened.
- Select **Save NVRAM** to save it manually.

EEPROM loading and saving, along with the correct DIP-switch mapping, requires
starting the core through the supplied MRA.

---

## ROMs

```text
                                *** Attention ***

ROMs are not included. Use the supplied Major Havoc MRA with the matching MAME
Major Havoc Rev 3 ROM set. The MRA verifies every program ROM, vector ROM, and
AVG state PROM by CRC.

Quick reference for MiSTer SD-card placement:

/_Arcade/Major Havoc.mra
/_Arcade/cores/MajorHavoc.rbf
/games/mame/mhavoc.zip
```

See the
[MiSTer Arcade ROM guide](https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms)
for other supported ROM-folder layouts.

---

## Compilation

The project uses **Quartus Prime Lite 17.0** and targets the Cyclone V FPGA on
the Terasic DE10-Nano.

1. Open `MajorHavoc.qpf` in Quartus.
2. Run the complete compilation flow.
3. Find the generated `MajorHavoc.rbf` in `output_files/`.

Production source files are listed in `files.qip`. Core-specific RTL is under
`rtl/`; `sys/` contains the standard MiSTer framework.

---

## Credits and Acknowledgments

- **Major Havoc:** Atari, 1983.
- **MiSTer Major Havoc core, AVG, renderer, and integration:** Videodr0me.
- **Vector drawer foundation:** Jeroen Domburg.
- **POKEY foundation:** MikeJ and FPGAArcade contributors.
- **T65 CPU core:** Daniel Wallner and subsequent T65 maintainers.
- **MiSTer platform:** Sorgelig and the MiSTer community.

---

## License

See [LICENSE](LICENSE) and the headers of individual source files for the terms
that apply to this project and its incorporated components.
