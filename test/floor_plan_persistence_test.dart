import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ios_roomplan/ios_roomplan.dart';
import 'package:ios_roomplan/src/floor_plan/services/merged_floor_plan_layout_service.dart';
import 'package:ios_roomplan/src/floor_plan/services/room_sample_location_service.dart';

void main() {
  late Directory directory;
  late File pdf;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ios_roomplan_test_');
    pdf = File('${directory.path}/room.pdf');
    await pdf.writeAsString('%PDF-1.4\n%%EOF');
  });

  tearDown(() async => directory.delete(recursive: true));

  test('edited surfaces and scan duration survive save and reload', () async {
    final scan = ScanResult.fromJson({
      'room': {'walls': []},
      'metadata': {'scanDuration': 12.5},
    });
    const surface = PlanSurfaceSnapshot(
      kind: 'wall',
      label: 'Edited wall',
      centerX: 2,
      centerY: -1,
      angle: 0.75,
      length: 4,
      depth: 0.12,
    );
    await FloorPlanPdfService.saveScanGeometry(
      scanResult: scan,
      roomName: 'Edited room',
      pdfFile: pdf,
      surfaceSnapshots: [surface],
      detectFurniture: false,
    );
    // Verify the embedded payload can reopen without its JSON sidecar.
    expect(await pdf.readAsString(), contains('%%IOS_ROOMPLAN_JSON_START%%'));
    await File('${directory.path}/room.roomplan.json').delete();
    final restored = await FloorPlanPdfService.loadScanGeometry(pdf);
    expect(restored, isNotNull);
    expect(restored!.name, 'Edited room');
    expect(restored.surfaceSnapshots!.single.toJson(), surface.toJson());
    expect(
      restored.scanResult.metadata.scanDuration,
      const Duration(milliseconds: 12500),
    );
    expect(restored.detectFurniture, isFalse);
  });

  test('merge placements and north rotation survive reload', () async {
    const rooms = [
      MergedFloorPlanLayoutEntry(
        roomScanPath: '/room-a.pdf',
        offsetX: -3.25,
        offsetY: 2.5,
        rotation: 1.2,
      ),
      MergedFloorPlanLayoutEntry(
        roomScanPath: '/room-b.pdf',
        offsetX: 4.5,
        offsetY: -2,
        rotation: -0.5,
      ),
    ];
    await MergedFloorPlanLayoutService.saveForPdf(
      pdfFile: pdf,
      rooms: rooms,
      northRotationRadians: 0.8,
    );
    final restored = await MergedFloorPlanLayoutService.loadForPdf(pdf);
    expect(
      restored.map((e) => e.toJson()).toList(),
      rooms.map((e) => e.toJson()).toList(),
    );
    expect(
      await MergedFloorPlanLayoutService.loadNorthRotationForPdf(pdf),
      0.8,
    );
  });

  test('annotation positions and rotation survive reload', () async {
    const marker = RoomSampleLocation(
      sampleRefId: 'A',
      label: 'Sample A',
      x: 0.25,
      y: 0.75,
      localX: -2,
      localY: 1,
    );
    await RoomSampleLocationService.saveForPdf(
      pdfFile: pdf,
      locations: [marker],
      rotationRadians: 0.4,
    );
    final restored = await RoomSampleLocationService.loadStateForPdf(pdf);
    expect(restored.rotationRadians, 0.4);
    expect(restored.locations.single.toJson(), marker.toJson());
  });
}
