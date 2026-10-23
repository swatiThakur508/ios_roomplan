import 'package:flutter_test/flutter_test.dart';
import 'package:ios_roomplan_example/main.dart';

void main() {
  testWidgets('example exposes real room scanning workflow', (tester) async {
    await tester.pumpWidget(const RoomPlanExampleApp());
    expect(find.text('Scan room'), findsOneWidget);
    expect(
      find.text('Scan a real room to save its 2D floor plan and 3D model.'),
      findsOneWidget,
    );
  });
}
