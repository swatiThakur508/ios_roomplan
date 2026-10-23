# Contributing

Thanks for helping improve `ios_roomplan`. Please keep changes focused on the
plugin's iOS RoomPlan capture flow, 2D PDF output, 3D USDZ export, and the
example that demonstrates them.

## Development setup

- Use Flutter 3.35 or later and Dart 3.9 or later.
- Use macOS with Xcode and CocoaPods for iOS builds.
- Real capture requires a supported LiDAR-equipped iPhone or iPad running iOS
  16 or later. The simulator can be used to check compilation only.

## Before opening a pull request

1. Run `dart format` on changed Dart files.
2. Run `dart analyze lib test example/lib` and resolve new diagnostics.
3. Run package and example tests with `flutter test` from the package root and
   `flutter test` from `example/`.
4. Build the iOS example with `flutter build ios --no-codesign` from `example/`.
5. For changes affecting capture, permissions, PDF output, USDZ export, or Quick
   Look, verify the flow on a supported physical device when available.
6. Update README, CHANGELOG, or public API documentation when behavior changes.

## Release checklist

- Confirm all code, documentation, and assets can be redistributed under the
  package's MIT license.
- Update the version in `pubspec.yaml` and add the release notes to
  `CHANGELOG.md`.
- Run `dart pub publish --dry-run` and review every listed file and warning.
- Publish only after the package contents and physical-device behavior are
  ready for users.
