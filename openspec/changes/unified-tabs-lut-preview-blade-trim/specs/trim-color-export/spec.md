## ADDED Requirements

### Requirement: Grouped edit menus
The system SHALL group My Takes row actions and Review toolbar actions into `Menu` sections: "Adjust" (Trim, Blade/Split at Playhead, Delete Selected Segment) and "Color" (LUT) and "Output" (Save to Photos, Share), consistently across swipe trailing menu, context menu, and the Review toolbar ellipsis. Disabled states SHALL reflect current preconditions (e.g., Blade disabled at ends, Delete disabled with no selection, Save disabled while exporting).

#### Scenario: Row swipe menu shows grouped sections
- **WHEN** the user swipes a take row or long-presses for the context menu
- **THEN** the menu shows Section "Adjust" with Trim / Blade / Delete, Section "Color" with LUT submenu, Section "Output" with Save/Share, in that order

#### Scenario: Review toolbar ellipsis mirrors row menu
- **WHEN** the user opens the Review toolbar `...` menu
- **THEN** it shows the same three sections and disabled-state logic as the My Takes row menu

## MODIFIED Requirements

### Requirement: GPU 3D LUT color grading via CoreImage Metal
The system SHALL apply `.cube` 3D LUT color tables through `CIFilter.colorCube` running on the Metal GPU, providing four built-in presets: Natural, Warm Studio, Cinematic Contrast, Clean Monochrome, and SHALL render a color preview swatch per preset in the picker.

#### Scenario: User selects Warm Studio preset
- **WHEN** user selects Warm Studio before export
- **THEN** the system loads the Warm Studio `cubeData` (64×64×64) and applies `CIFilter.colorCube(cubeDimension: 64)` via `CIContext(mtlDevice:)` to the exported frames

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
