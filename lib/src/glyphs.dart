import 'package:prism_ui/icons/icons.dart';

abstract final class Glyphs2 {
  static const nodes = Glyph([
    GlyphBox(3.6, 4, 20.4, 10.4, 2.4),
    GlyphBox(3.6, 13.6, 20.4, 20, 2.4),
    GlyphCircle(7.4, 7.2, 1.1, role: GlyphRole.detail, solid: true),
    GlyphCircle(7.4, 16.8, 1.1, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(11.4, 7.2),
      GlyphVertex(16.6, 7.2),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(11.4, 16.8),
      GlyphVertex(16.6, 16.8),
    ], role: GlyphRole.detail),
  ]);

  static const grid = Glyph([
    GlyphBox(3.8, 3.8, 10.4, 10.4, 2.4),
    GlyphCircle(16.9, 7.1, 3.3),
    GlyphBox(3.8, 13.6, 10.4, 20.2, 2.4),
    GlyphBox(13.6, 13.6, 20.2, 20.2, 2.4),
  ]);

  static const agents = Glyph([
    GlyphBox(5.4, 5.4, 18.6, 18.6, 4),
    GlyphBox(9.4, 9.4, 14.6, 14.6, 1.6, role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(9, 2.6),
      GlyphVertex(9, 5.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15, 2.6),
      GlyphVertex(15, 5.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9, 18.6),
      GlyphVertex(9, 21.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15, 18.6),
      GlyphVertex(15, 21.4),
    ], role: GlyphRole.line),
  ]);

  static const sliders = Glyph([
    GlyphPolyline([
      GlyphVertex(3.8, 7.2),
      GlyphVertex(11.4, 7.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(19, 7.2),
      GlyphVertex(20.2, 7.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3.8, 16.8),
      GlyphVertex(5, 16.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12.6, 16.8),
      GlyphVertex(20.2, 16.8),
    ], role: GlyphRole.line),
    GlyphCircle(15.2, 7.2, 2.6),
    GlyphCircle(8.8, 16.8, 2.6),
  ]);

  static const search = Glyph([
    GlyphCircle(10.8, 10.8, 6.4, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15.6, 15.6),
      GlyphVertex(20.4, 20.4),
    ], role: GlyphRole.line),
  ]);

  static const bolt = Glyph([
    GlyphPolyline([
      GlyphVertex(13.4, 3.6),
      GlyphVertex(6.6, 13.6, 1),
      GlyphVertex(11.4, 13.6),
      GlyphVertex(10.6, 20.4),
      GlyphVertex(17.4, 10.4, 1),
      GlyphVertex(12.6, 10.4),
    ], closed: true),
  ]);

  static const relay = Glyph([
    GlyphPolyline([
      GlyphVertex(4, 8.4),
      GlyphVertex(18.5, 8.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(15, 5),
      GlyphVertex(18.8, 8.4, 0.8),
      GlyphVertex(15, 11.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(20, 15.6),
      GlyphVertex(5.5, 15.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9, 12.2),
      GlyphVertex(5.2, 15.6, 0.8),
      GlyphVertex(9, 19),
    ], role: GlyphRole.line),
  ]);

  static const terminal = Glyph([
    GlyphBox(3.4, 4.4, 20.6, 19.6, 3),
    GlyphPolyline([
      GlyphVertex(7.4, 9.6),
      GlyphVertex(10.4, 12, 0.6),
      GlyphVertex(7.4, 14.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(12.6, 14.8),
      GlyphVertex(16.6, 14.8),
    ], role: GlyphRole.detail),
  ]);

  static const globe = Glyph([
    GlyphCircle(12, 12, 8.6),
    GlyphOval(8, 3.6, 16, 20.4, role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(3.8, 12),
      GlyphVertex(20.2, 12),
    ], role: GlyphRole.detail),
  ]);

  static const ping = Glyph([
    GlyphPolyline([
      GlyphVertex(3.6, 13.4),
      GlyphVertex(8.2, 13.4),
      GlyphVertex(10.6, 6.4, 0.8),
      GlyphVertex(13.4, 17.6, 0.8),
      GlyphVertex(15.8, 13.4),
      GlyphVertex(20.4, 13.4),
    ], role: GlyphRole.line),
  ]);

  static const plus = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 4.6),
      GlyphVertex(12, 19.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(4.6, 12),
      GlyphVertex(19.4, 12),
    ], role: GlyphRole.line),
  ]);

  static const radar = Glyph([
    GlyphCircle(12, 12, 8.6),
    GlyphCircle(12, 12, 4.2, role: GlyphRole.detail),
    GlyphCircle(12, 12, 1.1, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(12, 12),
      GlyphVertex(17.6, 7.8),
    ], role: GlyphRole.detail),
  ]);

  static const checklist = Glyph([
    GlyphPolyline([
      GlyphVertex(10, 6.6),
      GlyphVertex(20, 6.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(10, 12),
      GlyphVertex(20, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(10, 17.4),
      GlyphVertex(20, 17.4),
    ], role: GlyphRole.line),
    GlyphBox(3.6, 4.8, 7.2, 8.4, 1.2),
    GlyphBox(3.6, 10.2, 7.2, 13.8, 1.2),
    GlyphBox(3.6, 15.6, 7.2, 19.2, 1.2),
  ]);

  static const arrowDown = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 5),
      GlyphVertex(12, 19),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(6.4, 13.4),
      GlyphVertex(12, 19.4, 0.8),
      GlyphVertex(17.6, 13.4),
    ], role: GlyphRole.line),
  ]);

  static const arrowUp = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 19),
      GlyphVertex(12, 5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(6.4, 10.6),
      GlyphVertex(12, 4.6, 0.8),
      GlyphVertex(17.6, 10.6),
    ], role: GlyphRole.line),
  ]);

  static const sun = Glyph([
    GlyphCircle(12, 12, 4.2),
    GlyphPolyline([
      GlyphVertex(12, 3.2),
      GlyphVertex(12, 5),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(12, 19),
      GlyphVertex(12, 20.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3.2, 12),
      GlyphVertex(5, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(19, 12),
      GlyphVertex(20.8, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(5.8, 5.8),
      GlyphVertex(7.1, 7.1),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16.9, 16.9),
      GlyphVertex(18.2, 18.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(18.2, 5.8),
      GlyphVertex(16.9, 7.1),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(7.1, 16.9),
      GlyphVertex(5.8, 18.2),
    ], role: GlyphRole.line),
  ]);

  static const laptop = Glyph([
    GlyphBox(5.2, 5, 18.8, 15, 2),
    GlyphPolyline([
      GlyphVertex(3.4, 18.6),
      GlyphVertex(20.6, 18.6),
    ], role: GlyphRole.line),
  ]);

  static const monitor = Glyph([
    GlyphBox(3.8, 5, 20.2, 16, 2.2),
    GlyphPolyline([
      GlyphVertex(12, 16),
      GlyphVertex(12, 19.4),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(8.4, 19.4),
      GlyphVertex(15.6, 19.4),
    ], role: GlyphRole.line),
  ]);

  static const phone = Glyph([
    GlyphBox(7, 3.4, 17, 20.6, 3),
    GlyphPolyline([
      GlyphVertex(10.6, 17.2),
      GlyphVertex(13.4, 17.2),
    ], role: GlyphRole.detail),
  ]);

  static const key = Glyph([
    GlyphCircle(8.4, 8.4, 4.6),
    GlyphCircle(7.6, 7.6, 1.2, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(11.9, 11.9),
      GlyphVertex(20, 20),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16.2, 16.2),
      GlyphVertex(18.4, 14),
    ], role: GlyphRole.line),
  ]);

  static const trash = Glyph([
    GlyphPolyline([
      GlyphVertex(4.6, 7.2),
      GlyphVertex(19.4, 7.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9.6, 4.2),
      GlyphVertex(14.4, 4.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(6.6, 7.2),
      GlyphVertex(7.6, 20, 1.6),
      GlyphVertex(16.4, 20, 1.6),
      GlyphVertex(17.4, 7.2),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(10.2, 11),
      GlyphVertex(10.2, 16.2),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(13.8, 11),
      GlyphVertex(13.8, 16.2),
    ], role: GlyphRole.detail),
  ]);

  static const refresh = Glyph([
    GlyphArc(12, 12, 7.4, -0.55, -4.9, role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(19.4, 3.8),
      GlyphVertex(19.4, 8.6, 0.6),
      GlyphVertex(14.6, 8.6),
    ], role: GlyphRole.line),
  ]);

  static const logout = Glyph([
    GlyphPolyline([
      GlyphVertex(13.6, 4.4),
      GlyphVertex(5.4, 4.4),
      GlyphVertex(5.4, 19.6),
      GlyphVertex(13.6, 19.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(11, 12),
      GlyphVertex(20.2, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(16.6, 8.4),
      GlyphVertex(20.4, 12, 0.8),
      GlyphVertex(16.6, 15.6),
    ], role: GlyphRole.line),
  ]);

  static const schedule = Glyph([
    GlyphCircle(12, 12, 8.4),
    GlyphPolyline([
      GlyphVertex(12, 7.4),
      GlyphVertex(12, 12),
      GlyphVertex(15.4, 13.8),
    ], role: GlyphRole.detail),
  ]);

  static const photo = Glyph([
    GlyphBox(3.8, 4.8, 20.2, 19.2, 3),
    GlyphCircle(9, 9.6, 1.6, role: GlyphRole.detail, solid: true),
    GlyphPolyline([
      GlyphVertex(5.6, 16.6),
      GlyphVertex(9.8, 12.8, 0.8),
      GlyphVertex(13.2, 15.4),
      GlyphVertex(16.2, 12.8, 0.8),
      GlyphVertex(18.6, 15.2),
    ], role: GlyphRole.detail),
  ]);

  static const bell = Glyph([
    GlyphPath('M5.4 17.2 H18.6 L17.2 15.2 V11 A5.2 5.2 0 0 0 6.8 11 V15.2 Z'),
    GlyphPolyline([
      GlyphVertex(10.2, 20.2),
      GlyphVertex(13.8, 20.2),
    ], role: GlyphRole.line),
  ]);

  static const doc = Glyph([
    GlyphPolyline([
      GlyphVertex(6, 3.8, 1.6),
      GlyphVertex(14, 3.8),
      GlyphVertex(18.6, 8.4),
      GlyphVertex(18.6, 20.2, 1.6),
      GlyphVertex(6, 20.2, 1.6),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(14, 4.2),
      GlyphVertex(14, 8.4),
      GlyphVertex(18.2, 8.4),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(9.2, 12.6),
      GlyphVertex(15.4, 12.6),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(9.2, 16.2),
      GlyphVertex(15.4, 16.2),
    ], role: GlyphRole.detail),
  ]);

  static const keyboard = Glyph([
    GlyphBox(2.6, 6.2, 21.4, 17.8, 3),
    GlyphPolyline([
      GlyphVertex(6.6, 10.2),
      GlyphVertex(7.4, 10.2),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(11.6, 10.2),
      GlyphVertex(12.4, 10.2),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(16.6, 10.2),
      GlyphVertex(17.4, 10.2),
    ], role: GlyphRole.detail),
    GlyphPolyline([
      GlyphVertex(7.4, 14.2),
      GlyphVertex(16.6, 14.2),
    ], role: GlyphRole.detail),
  ]);

  /// The d-pad that opens the arrow keys.
  static const dpad = Glyph([
    GlyphPolyline([
      GlyphVertex(12, 3.4),
      GlyphVertex(12, 20.6),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(3.4, 12),
      GlyphVertex(20.6, 12),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9.2, 6.2),
      GlyphVertex(12, 3.4, 0.6),
      GlyphVertex(14.8, 6.2),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(9.2, 17.8),
      GlyphVertex(12, 20.6, 0.6),
      GlyphVertex(14.8, 17.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(6.2, 9.2),
      GlyphVertex(3.4, 12, 0.6),
      GlyphVertex(6.2, 14.8),
    ], role: GlyphRole.line),
    GlyphPolyline([
      GlyphVertex(17.8, 9.2),
      GlyphVertex(20.6, 12, 0.6),
      GlyphVertex(17.8, 14.8),
    ], role: GlyphRole.line),
  ]);

  /// A pen, for the Compose sheet.
  static const compose = Glyph([
    GlyphPolyline([
      GlyphVertex(4.4, 19.6),
      GlyphVertex(5.2, 14.6),
      GlyphVertex(15.8, 4, 1.4),
      GlyphVertex(20, 8.2, 1.4),
      GlyphVertex(9.4, 18.8),
    ], closed: true),
    GlyphPolyline([
      GlyphVertex(13.6, 6.8),
      GlyphVertex(17.2, 10.4),
    ], role: GlyphRole.detail),
  ]);
}
