# Hold Detection Pipeline Redesign

## Goal

Replace the current classify-then-segment pipeline with a proper segment-first approach: use `VNDetectContoursRequest` to find hold shapes, classify each shape by interior color, then let the user confirm which color group is their route before fingerprinting and matching.

## Problem with the current pipeline

`HoldSegmenter` today classifies every pixel into one of 20 fixed hue bins, then runs BFS within the dominant bin. This means:

- Classification happens before segmentation — small holds in non-dominant colors are silently dropped.
- The "dominant" color is often the wall or the most common hold color, not the user's route.
- Fixed hue bins miss holds whose color straddles two bins.

## Architecture

Three stages:

### Stage 1 — Segment (Vision)

`HoldSegmenter.segmentHoldGroups(in: CIImage) -> [HoldGroup]`

1. **Preprocess:** Scale frame to 512px on the long edge via `CILanczosScaleTransform`. Apply `CIColorControls` with contrast 1.5 to sharpen hold-wall boundaries.
2. **Contour detection:** `VNDetectContoursRequest` with `contrastAdjustment = 2.0` and `maximumImageDimension = 512`. Take top-level contours only (outer hold boundary, not inner holes).
3. **Area filter:** Convert each contour's normalised bounding box to pixel area. Discard contours smaller than 0.05% of frame area (screw heads, texture) or larger than 10% (wall background). This window covers crimps through jugs.
4. **Interior color sampling:** Render each surviving contour's `normalizedPath` into a 1-bit CoreGraphics mask. Sample original pixels under the mask. Compute mean HSV. Discard if mean saturation < 0.25 (gray plastic, unpainted wood).
5. **Hue grouping:** Assign each contour to one of 20 hue bins by its mean hue. Merge contours within 1 bin of each other into a single `HoldGroup`. Sort groups descending by hold count.
6. **Cross-frame merge:** Run stages 1–5 on 3 frames extracted at 0%, 50%, and 100% of video duration. Deduplicate holds across frames: two centroids within 5% of frame width are the same hold — keep the one from the frame with higher contour confidence score.

### Stage 2 — User confirms color (new import step)

After detection, `ImportPipeline.analyze()` returns a new result case:

```swift
case colorSelection(image: UIImage, groups: [HoldGroup], assetIdentifier: String)
```

`ImportState` gains a matching case:

```swift
case selectColor(image: UIImage, groups: [HoldGroup], assetIdentifier: String)
```

The import flow shows a **color picker screen**:
- The video frame with all hold groups drawn in their real colors (60% opacity until a selection is made).
- A horizontal scrollable pill row — one pill per `HoldGroup`, showing its color and hold count.
- Tapping a pill highlights that group (full opacity) and dims all others.
- **"This is my route →"** button, disabled until a pill is selected.
- **"Can't tell / skip"** text link below the button: auto-selects the largest group, flags confidence as low, and proceeds to the existing ambiguous confirmation screen.

### Stage 3 — Fingerprint + match (unchanged)

`ImportViewModel.confirmColor(group: HoldGroup, assetIdentifier: String, context: ModelContext) async` runs:

1. `FingerprintGenerator.generate(from: group.candidates, dominantHue: group.hue)` — produces `RouteDescriptor` from the confirmed group's centroids.
2. `RouteMatcher.match(descriptor:hue:against:)` — unchanged hue-gate + L2 distance logic.
3. Transitions to `.matched`, `.ambiguous`, or `.newRoute` exactly as today.

The `RouteFingerprint` data model is unchanged: still `[Float]` pairwise distances + `dominantHue`. The difference is those values now reflect the user's actual route rather than an algorithmic guess.

## Import flow comparison

**Before:**
```
Pick video → Detecting holds… → Matched / New Route / No holds / Error
```

**After:**
```
Pick video → Detecting holds… → Pick your route color → Matched / New Route / No holds / Error
```

## Error handling

| Situation | Behaviour |
|---|---|
| No contours survive area filter | `noHoldsDetected` → manual pick fallback |
| All contours fail saturation check | `noHoldsDetected` → manual pick fallback |
| `VNDetectContoursRequest` throws on a frame | Skip that frame; if all 3 fail → `noHoldsDetected` |
| User taps "Can't tell / skip" | Auto-select largest group, low confidence, → ambiguous screen |
| `confirmColor` finds no fingerprint match | `newRoute` state |
| iCloud video not on device | Handled by existing `FrameExtractor` (network allowed, 30s timeout) |

## Files changed

| File | Change |
|---|---|
| `Detection/HoldSegmenter.swift` | Replace `detectHolds` / `detectAllHoldGroups` with `segmentHoldGroups` using `VNDetectContoursRequest` |
| `Detection/ImportPipeline.swift` | `analyze()` returns `.colorSelection` instead of auto-picking; add `analyzeGroup()` helper for Stage 3 |
| `Detection/Types.swift` | Add `ImportPipelineResult.colorSelection` case |
| `ViewModels/ImportViewModel.swift` | Add `selectColor` state case; add `confirmColor()` and `skipColorSelection()` methods |
| `Views/ImportFlowView.swift` | Add `selectColorView` for the color picker step |
| `Views/HoldsVisualizationSheet.swift` | Update `detect()` to call `segmentHoldGroups` instead of `detectAllHoldGroups` |

## Out of scope

- Changes to `RouteMatcher` logic (hue gate, L2 distance thresholds).
- Changes to `RouteFingerprint` data model schema.
- Training a CoreML model (future work if Vision contours prove insufficient).
