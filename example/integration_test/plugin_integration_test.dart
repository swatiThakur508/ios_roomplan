import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ios_roomplan/ios_roomplan.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native RoomPlan capability method is registered', (
    tester,
  ) async {
    expect(await RoomPlanScanner.isSupported(), isA<bool>());
  });
}
