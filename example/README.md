# Example app

The example demonstrates these `ios_roomplan` workflows:

1. Check RoomPlan support and scan a room in Apple's native capture interface.
2. Create, preview, and share the 2D floor-plan PDF and 3D USDZ model.
3. Save a durable scan record and copies of both output files in app support storage.
4. Reopen saved scans, review scan hints, rename or delete entries, and copy structured scan JSON.
5. Create a combined PDF with one page per saved room.
6. Scan connected rooms together on iOS 17+, producing per-room scan data, a multi-page 2D PDF, and one merged 3D USDZ structure.

From the repository root, prepare and run the example app with:

```sh
cd example
flutter pub get
cd ios
pod install
cd ..
flutter run
```

Run `flutter pub get` before `pod install`; it creates `ios/Flutter/Generated.xcconfig`, which the Podfile requires.

Run the app on a physical supported iPhone Pro / Pro Max from iPhone 12 Pro onward, or a LiDAR-equipped iPad Pro, using iOS 16 or later. Single-room capture works on iOS 16+; multi-room capture needs iOS 17+. The iOS Simulator can build the app but cannot perform a RoomPlan scan. Grant camera permission when prompted.

For connected rooms, tap **Scan connected rooms (iOS 17+)**. After each room, choose to scan another adjacent room or finish the structure. RoomPlan builds the merged USDZ from rooms captured in the same shared coordinate space; independently scanned rooms are not automatically aligned. Keep tracking stable as you move through doorways. The 2D PDF contains one page per room, and the merged 3D model is available to preview and share.

The camera opens directly when a scan starts. After you finish a room, the native capture screen shows a centered progress indicator while RoomPlan processes it. Processing time varies with device and scan complexity.

Single-room scans remain in the app's private support directory between launches. Multi-room outputs are kept for the current example session; copy them into app-managed storage if they need to remain available after the app closes. JSON exports contain structured scan data and metadata; they do not include the PDF or USDZ bytes. Share buttons open the iOS system share sheet. For the full integration guide, data model details, device support, units, and limitations, see the [main README](../README.md).
