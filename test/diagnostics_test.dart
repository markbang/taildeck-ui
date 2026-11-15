import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/diagnostics.dart';

void main() {
  test('records the error and the top of its stack', () {
    final errors = AppErrors();
    errors.record(
      StateError('Too many elements'),
      StackTrace.fromString('#0 a\n#1 b\n#2 c\n#3 d\n#4 e\n#5 f\n#6 g'),
    );
    expect(errors.text, contains('Bad state: Too many elements'));
    expect(errors.text, contains('#5 f'));
    expect(errors.text, isNot(contains('#6 g')));
  });

  test('keeps only the last few errors', () {
    final errors = AppErrors();
    for (var i = 0; i < 50; i++) {
      errors.record('error $i', null);
    }
    expect(errors.lines.length, 40);
    expect(errors.text, contains('error 49'));
    expect(errors.text, isNot(contains('error 0\n')));
  });

  test('clears', () {
    final errors = AppErrors()..record('boom', null);
    errors.clear();
    expect(errors.text, isEmpty);
  });
}
