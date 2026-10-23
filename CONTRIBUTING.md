# Extraction and release notes

The plugin is maintained independently from the original host application.
Host-specific persistence and branding are excluded from the package.

Room capture is implemented against Apple's RoomPlan API. Method and event
channels use the ios_roomplan namespace. Scanner settings use namespaced preferences.
Database-bound room/sample inputs were replaced by title, RoomPlanAnnotation, and
an asynchronous onSaved callback. The merge editor takes logo data directly.
The application-specific rolling switch was replaced with Flutter's Switch.

Before publication:

1. Confirm the package name is accepted by pub.dev; no reservation is made locally.
2. Create the intended source repository and add its real repository and issue URLs
   to pubspec.yaml. Confirm the GEITPL author metadata in the podspec.
3. Confirm ownership and licensing for every code and media asset included in
   the release.
4. Test scanning, cancellation, permission denial, repeated scans, native USDZ
   export/preview, 2D edits, PDF export, and manual merging on a physical device.
5. If Swift Package Manager consumers must be supported, add and verify the native
   Swift package layout and resource declaration; only CocoaPods is configured now.
6. Review documented editing and serialization limitations before promising API
   stability or full 3D editing. Consider a prerelease until device validation passes.
7. Run analysis, unit/example tests, the iOS build, and dart pub publish --dry-run.
8. Review the publication file list, then publish deliberately with dart pub publish.

The PDF/image dependency range excludes image 4.11 because its PNG decoder calls
archive APIs not supplied by the archive range accepted by pdf 3.12. Reevaluate
that range when upgrading the PDF dependency.

The installed Flutter 3.35.7 tool expects an analysis-server snapshot absent from
this SDK installation; dart analyze works and is used for source analysis here.

Validated during extraction:

- dart analyze: no issues.
- flutter test: 48 package tests pass, including geometry/marker/layout persistence.
- Example flutter test: widget smoke test passes.
- Example flutter build ios --no-codesign: succeeds.
- dart pub publish --dry-run: package validates with one metadata warning for
  missing homepage/repository; configure the real repository before publishing.

No physical-device capture test or publication was performed.
