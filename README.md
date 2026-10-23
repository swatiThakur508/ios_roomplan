# ios_roomplan

A Flutter plugin for scanning real rooms on supported iOS devices and saving a
2D floor plan PDF and a 3D USDZ model. The package uses Apple's RoomPlan API
for capture and Quick Look to preview the saved files.

## Requirements

- Flutter 3.35 or later and Dart 3.9 or later.
- iOS 16 or later on a RoomPlan-compatible device with LiDAR.
- Xcode and CocoaPods to build the iOS app.
- Camera permission in the host app.

RoomPlan scanning is iOS-only. A simulator can build the example but cannot scan
a room. `RoomPlanScanner.isSupported()` reports whether capture is available on
the current device.

## Install

The package has not yet been published to pub.dev. Until its first release, add
it from GitHub:

```yaml
dependencies:
  ios_roomplan:
    git:
      url: https://github.com/swatiThakur508/ios_roomplan.git
      ref: main
```

After publication, use the version shown on pub.dev:

```yaml
dependencies:
  ios_roomplan: ^0.1.0
```

For local plugin development, use a path dependency instead:

```yaml
dependencies:
  ios_roomplan:
    path: ../ios_roomplan
```

Set the host app's iOS deployment target to 16.0 or later. Add a camera usage
description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan a room to create a floor plan and 3D model.</string>
```

## Scan a room

`FloorRoomScanPage` presents the scan workflow and returns both saved files:

```dart
import 'package:flutter/material.dart';
import 'package:ios_roomplan/ios_roomplan.dart';

Future<void> scanRoom(BuildContext context) async {
  final result = await Navigator.of(context).push<FloorRoomScanResult>(
    MaterialPageRoute(
      builder: (_) => const FloorRoomScanPage(initialName: 'Living room'),
    ),
  );

  if (!context.mounted || result == null) return; // The user cancelled.

  final floorPlanPdf = result.pdfFile;
  final roomModel = result.modelFile;
  debugPrint('Saved ${result.name}: ${floorPlanPdf.path}, ${roomModel.path}');
}
```

The page checks device support, requests camera access when needed, shows scan
progress, and reports capture or save errors in the UI. Its settings control
which furniture, doors, and windows appear in the saved 2D plan and the minimum
detection confidence. They do not adjust LiDAR or RoomPlan sensor precision;
that is determined by the device and Apple's RoomPlan implementation. The USDZ
represents the native capture before the 2D output filters are applied.

For lower-level access to the native scan data, use `RoomPlanScanner` directly:

```dart
final scanner = RoomPlanScanner();
try {
  final scan = await scanner.startScanning();
  if (scan != null) {
    debugPrint('Captured ${scan.room.walls.length} walls');
  }
} finally {
  scanner.dispose();
}
```

`startScanning()` returns `null` when the capture is cancelled. Subscribe to
`scanner.onScanResult` for live geometry updates. Call `stopScanning()` to end
an active capture programmatically.

## Preview the saved files

Both files can be opened with Apple's Quick Look viewer:

```dart
await RoomPlanModelViewer.previewFloorPlan(result.pdfFile); // 2D PDF
await RoomPlanModelViewer.preview(result.modelFile); // 3D USDZ
```

The PDF is saved in the app's documents directory. The USDZ is exported to the
system temporary directory; copy it to app-managed persistent storage if it
needs to remain available later. Keep or copy the PDF as well if your app needs
to manage its lifecycle independently.

## Run the example

```sh
cd example
flutter pub get
flutter run
```

Run it on a supported physical iPhone or iPad, grant camera access, complete a
scan, and use the example's buttons to preview the 2D PDF and 3D USDZ.

## Errors

Capture can fail if the device is unsupported, camera access is denied, the
capture is cancelled, RoomPlan cannot process the room, or an output file
cannot be created. Catch errors around the navigation/scan call and present an
appropriate message. `RoomPlanException` subclasses expose readable messages
for common native failures.

## License

MIT. See [LICENSE](LICENSE).
