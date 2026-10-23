# ios_roomplan

An iOS Flutter plugin that scans a real room and saves two outputs: a 2D floor
plan PDF and a 3D USDZ model. The example app demonstrates this single workflow.

## Requirements

- Flutter 3.35 or later and Dart 3.9 or later.
- iOS 16 or later and a supported LiDAR-equipped device for scanning.
- A Mac with Xcode to build the iOS example.

The plugin reports unsupported devices, camera permission problems, scan errors,
and file export errors. A simulator can verify compilation but cannot perform a
real room scan.

## Install from a local checkout

```yaml
dependencies:
  ios_roomplan:
    path: ../ios_roomplan
```

Set the host app's iOS deployment target and Podfile platform to 16.0 or later.
Add a camera usage description to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Scan rooms to save a 2D floor plan and 3D model.</string>
```

## Scan and save

```dart
import 'package:flutter/material.dart';
import 'package:ios_roomplan/ios_roomplan.dart';

final result = await Navigator.of(context).push<FloorRoomScanResult>(
  MaterialPageRoute(
    builder: (_) => const FloorRoomScanPage(initialName: 'Living room'),
  ),
);

if (result != null) {
  final floorPlanPdf = result.pdfFile;
  final roomModel = result.modelFile;
  // Save these paths in your app if you need to reopen them later.
}
```

The scan page creates both files in the host app's documents directory. The
result contains the PDF and USDZ file paths. Use Quick Look to preview the 3D
model:

```dart
await RoomPlanModelViewer.preview(result.modelFile);
```

The 2D floor plan is a PDF and can also be previewed with Quick Look:

```dart
await RoomPlanModelViewer.previewFloorPlan(result.pdfFile);
```

The plugin does not upload, share, or add files to the Photos app. Copy the
files to storage managed by your application if you need a different retention
or backup policy.

## Run the example

```bash
cd example
flutter pub get
flutter run
```

Use a supported physical iPhone or iPad, grant camera access, complete a scan,
and save the generated PDF and USDZ. The example can preview both saved files
in Quick Look and displays their local file paths.

## License

This project is distributed under the MIT License. See [LICENSE](LICENSE).
