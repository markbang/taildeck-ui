import 'package:flutter_test/flutter_test.dart';
import 'package:taildeck_ui/src/back.dart';

void main() {
  test('back closes the innermost page that is open', () {
    final stack = BackStack();
    final closed = <String>[];
    stack
      ..add(() {
        closed.add('settings section');
        return true;
      })
      ..add(() {
        closed.add('logs');
        return true;
      });

    expect(stack.closeTop(), isTrue);
    expect(closed, ['logs']);
  });

  test('a stack with nothing open lets the press through', () {
    final stack = BackStack()..add(() => false);
    expect(stack.closeTop(), isFalse);
    expect(BackStack().closeTop(), isFalse);
  });

  test('a removed handler is never asked', () {
    final stack = BackStack();
    bool close() => true;
    stack
      ..add(close)
      ..remove(close);
    expect(stack.closeTop(), isFalse);
  });
}
