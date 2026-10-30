# Changelog

## 0.2.0 - 2026-10-30

- Add iOS 17 multi-room capture using Apple's shared coordinate space and StructureBuilder, returning per-room scan data and a merged USDZ structure.
- Add a multi-room scan flow to the example, including a PDF page per room and persistent merged model output.
- Add a persistent scan library with list, load, rename, delete, and structured JSON import/export operations; saved scans can include durable PDF and USDZ copies.
- Add an iOS system share-sheet API for PDF and USDZ outputs.
- Return processed scan data from `FloorRoomScanPage` and add scan review suggestions for sparse walls and low-confidence detections.
- Expose floor-plan generation and multi-room PDF layout APIs from the package entry point.
- Expand the example app with saved-scan management, review hints, and a combined multi-room PDF workflow.
- Document scan retention, data-model limitations, calculations, and device support in the README.

## Unreleased

No unreleased changes.

## 0.1.2

- Use the published pub.dev package in the installation instructions.
- Remove the unused direct `image` dependency and use the version selected by
  `pdf`.

## 0.1.1

- Expand Dart API documentation for exceptions, confidence values, and
  measurement units.

## 0.1.0

- Add iOS room capture with Apple's RoomPlan API.
- Save a 2D floor plan as PDF and the native capture as USDZ.
- Preview the PDF and USDZ with Quick Look.
- Add scan progress, cancellation, device support checks, and capture/export
  error handling.
- Add a Flutter example for scanning and previewing both outputs.
