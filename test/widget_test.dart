// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:todoapp/helper/note_search.dart';

void main() {
  test('sanity check', () {
    expect(1 + 1, 2);
  });

  test(
    'note search accepts partial, unaccented and reordered Vietnamese words',
    () {
      const title = 'Kế hoạch học tập';

      expect(matchesNoteSearch(query: 'ke hoach', title: title), isTrue);
      expect(matchesNoteSearch(query: 'tap hoc', title: title), isTrue);
      expect(matchesNoteSearch(query: 'hoac', title: title), isTrue);
      expect(matchesNoteSearch(query: 'du lich', title: title), isFalse);
    },
  );
}
