import 'package:flutter_test/flutter_test.dart';
import 'package:pmis_deped/utils/id_generator.dart';

void main() {
  test('generate WFP id formats properly', () {
    final id = IDGenerator.generateWFP(2025, 3);
    expect(id, 'WFP-2025-0003');
  });

  test('generate activity id formats properly', () {
    final aid = IDGenerator.generateActivity('WFP-2025-0003', 7);
    expect(aid, 'ACT-WFP-2025-0003-07');
  });
}
