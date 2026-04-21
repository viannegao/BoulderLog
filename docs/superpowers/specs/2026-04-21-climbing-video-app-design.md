# Climbing Video Documentation App — Design Spec

**Date:** 2026-04-21
**Platform:** iOS (native)
**Status:** Approved

---

## Overview

A bouldering video documentation app that automatically groups climbing videos by route using on-device computer vision. Users import videos from their camera roll; the app detects which route is being climbed, highlights the holds, and groups all attempts together. Progress is tracked per route: attempt count, send status, and notes.

---

## Architecture

Four units, each with a single clear purpose:

### 1. Route Detection Engine
On-device CV pipeline (CoreImage + Vision framework). Given a video, produces a route fingerprint. Runs as a background task off the main thread. Has no knowledge of stored routes — takes a video in, returns a fingerprint out.

### 2. Route Matcher
Compares a new fingerprint against all stored `RouteFingerprint` records using Hausdorff distance on normalized keypoint sets. Returns a match result: `(routeId, confidence)` if above threshold, or `.noMatch` if below. Completely decoupled from the detection engine.

### 3. Data Store
SwiftData. Three models: `Route`, `Attempt`, `RouteFingerprint`. Videos are never copied — the app stores PHAsset identifiers and accesses videos from the Photos library directly.

### 4. UI Layer
SwiftUI. Three screens: Library, Route Detail, Import Flow. No network layer.

**Tech stack:** Swift, SwiftUI, SwiftData, Vision, CoreImage, AVFoundation, PhotosKit.

---

## Route Detection Pipeline

Triggered on video import. Steps run sequentially in a background Task:

1. **Frame extraction** — AVFoundation samples 5 frames evenly across the video duration.
2. **Hold segmentation** — CoreImage HSV color thresholding isolates distinct hue clusters per frame. Blobs below a minimum area threshold are discarded.
3. **Centroid extraction** — For the dominant color (largest blob cluster), compute the (x, y) centroid of each blob. These keypoints represent the route's hold layout.
4. **Perspective normalization** — Normalize all centroid coordinates to a [0,1] bounding box (min-max scaling across x and y). This handles scale and zoom variation. Full angle invariance (e.g. camera tilted sideways) is not guaranteed in v1; the Hausdorff distance metric provides some tolerance for small positional shifts.
5. **Fingerprint generation** — Encode the normalized keypoints as a compact `[Float]` descriptor: sorted pairwise relative distances between centroids, plus the dominant hue value.
6. **Route matching** — Compare the new fingerprint against all stored `RouteFingerprint` records. Hausdorff distance determines similarity. Result: best match + confidence score.
7. **Confirmation screen** — Always present the match result to the user before saving, with the detected holds overlay visible. User can override.

---

## Data Model

```swift
// SwiftData models

@Model class Route {
    var id: UUID
    var dominantColor: String       // hex color for library card
    var createdAt: Date
    var lastAttemptAt: Date
    var isSent: Bool
    var grade: String?              // user-assigned, e.g. "V6"
    var attempts: [Attempt]
}

@Model class Attempt {
    var id: UUID
    var assetIdentifier: String     // PHAsset local identifier
    var date: Date
    var isSend: Bool
    var notes: String
    var route: Route
}

@Model class RouteFingerprint {
    var routeId: UUID
    var descriptor: [Float]         // normalized pairwise centroid distances
    var dominantHue: Float
}
```

**Key decisions:**
- No video copying. Videos stay in Photos; app holds only PHAsset identifiers.
- `RouteFingerprint` is separate from `Route` so the matcher can load all fingerprints cheaply without pulling in the full object graph.
- Grade is optional and user-assigned — CV cannot reliably infer difficulty.
- Route names are never auto-generated. Default label is the dominant color (e.g. "Blue route"). User can rename from Route Detail.

---

## UI Screens

### Library
- Grid of route cards. Each card: color-tinted thumbnail, clip count badge, "SENT" badge if sent, route name, last attempt date.
- Filter chips: All / Sent / Projects (unsent routes).
- "+" button to import a new video.

### Route Detail
- Back navigation to Library.
- Stats bar: attempt count, send status (✓ or –), grade (if set).
- Chronological list of attempt items: video thumbnail, date, notes, send/attempt badge.
- Tap any attempt to play the video.

### Import Flow
1. PhotosPicker — user selects a video from camera roll.
2. Processing state — pipeline runs in background, spinner shown.
3. Confirmation screen:
   - Video preview with timestamp/duration.
   - "Matched Route" card with route color, name, confidence %, previous attempt count.
   - "Detected Holds" overlay — colored dots at centroid positions.
   - "Add as Attempt →" primary button.
   - Option to reassign to a different route or create new route.

---

## Error Handling

| Scenario | Behavior |
|---|---|
| Confidence < 70% | Show two options: "Add to [Route X]" or "This is a new route" — never auto-assign |
| No holds detected (bad lighting, blur) | Skip pipeline, show manual assignment screen with clear message: "Couldn't detect holds — pick manually" |
| PHAsset no longer available | Show placeholder in attempt list with "Video unavailable" label |
| Duplicate import (same PHAsset ID) | Detect on import, warn user: "This video is already logged" |

---

## Out of Scope (v1)

- Cloud sync or backup
- Social features / sharing
- Recording in-app
- Multi-gym management
- Route setter or gym metadata
- Any network requests
