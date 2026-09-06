## MODIFIED Requirements

### Requirement: GPU 3D LUT color grading via CoreImage Metal
The system SHALL apply `.cube` 3D LUT color tables through `CIFilter.colorCube` running on the Metal GPU, providing ten built-in presets — Natural, Warm Studio, Cinematic Contrast, Clean Monochrome, Golden Hour, Teal & Orange, Faded Film, Noir Punch, Vibrant Pop, Cool Morning — loaded size-aware (Adobe text parsed via `LUT_3D_SIZE` for 16/32/64; legacy raw-binary files detected by byte count, 4 MB meaning 64), and SHALL render a color preview swatch per preset in the picker.

#### Scenario: User selects Warm Studio preset
- **WHEN** user selects Warm Studio before export
- **THEN** the system loads the Warm Studio `cubeData` (64×64×64) and applies `CIFilter.colorCube(cubeDimension: 64)` via `CIContext(mtlDevice:)` to the exported frames

#### Scenario: User selects a SIZE-32 preset
- **WHEN** user selects Golden Hour before export
- **THEN** the system parses `LUT_3D_SIZE 32` and applies `CIFilter.colorCube(cubeDimension: 32)` with identical plumbing

#### Scenario: Natural is identity
- **WHEN** user selects Natural
- **THEN** the output matches the input frames (no visible color shift) and the system may skip the filter pass for performance; the preview swatch shows neutral gray

#### Scenario: Monochrome produces grayscale
- **WHEN** user selects Clean Monochrome
- **THEN** the exported video renders as grayscale with preserved luminance

#### Scenario: Trim and LUT combined
- **WHEN** user both trims and selects Cinematic Contrast
- **THEN** the system composes `timeRange` trimming and `colorCube` filtering in a single export pass (using `AVMutableComposition` + `CIImage` pipeline or `AVVideoComposition` with `CIFilter`) and produces a correctly trimmed and graded file

#### Scenario: LUT picker shows rendered swatches
- **WHEN** the user opens the LUT picker in Review
- **THEN** each row shows a 40×24 rendered swatch of that preset's transform (Natural = neutral gray, others tinted per their `.cube`) plus the display name; swatches are cached and regenerate when `.cube` data changes

#### Scenario: Swatch fallback
- **WHEN** a `.cube` file is missing or `cubeData` is nil
- **THEN** the row shows a tinted placeholder swatch and the export falls back to Natural behavior for that preset

## ADDED Requirements

### Requirement: Single-line actions row
The system SHALL render the Review actions row ("Save as New Take" + "Replace" side by side) on one line each at 320–430pt widths via `.lineLimit(1)` plus downscaling (no wrapping), preserving button styles and disabled states.

#### Scenario: Narrow-screen actions stay single-line
- **WHEN** Review renders on a 320pt-wide device
- **THEN** "Save as New Take" and "Replace" each occupy exactly one line without wrapping or clipping
