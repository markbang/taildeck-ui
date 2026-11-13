import 'package:prism_ui/icons/icons.dart';

abstract final class Glyphs2 {
  static const nodes = Glyph([
    GlyphBox(3.6, 4, 20.4, 10.4, 2.4, role: GlyphRole.line),
    GlyphBox(3.6, 13.6, 20.4, 20, 2.4, role: GlyphRole.line),
    GlyphCircle(7, 7.2, 0.9, role: GlyphRole.line, solid: true),
    GlyphCircle(7, 16.8, 0.9, role: GlyphRole.line, solid: true),
  ]);

  static const grid = Glyph([
    GlyphBox(3.8, 3.8, 10.4, 10.4, 2.4, role: GlyphRole.line),
    GlyphBox(13.6, 3.8, 20.2, 10.4, 2.4, role: GlyphRole.line),
    GlyphBox(3.8, 13.6, 10.4, 20.2, 2.4, role: GlyphRole.line),
    GlyphBox(13.6, 13.6, 20.2, 20.2, 2.4, role: GlyphRole.line),
  ]);

  static const agents = Glyph([
    GlyphBox(5.4, 5.4, 18.6, 18.6, 4, role: GlyphRole.line),
    GlyphBox(9.4, 9.4, 14.6, 14.6, 1.6, role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(9, 2.6), GlyphVertex(9, 5.4)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(15, 2.6), GlyphVertex(15, 5.4)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(9, 18.6), GlyphVertex(9, 21.4)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(15, 18.6), GlyphVertex(15, 21.4)], role: GlyphRole.line),
  ]);

  static const sliders = Glyph([
    GlyphPolyline([GlyphVertex(3.8, 7.2), GlyphVertex(20.2, 7.2)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(3.8, 16.8), GlyphVertex(20.2, 16.8)], role: GlyphRole.line),
    GlyphCircle(15.2, 7.2, 2.6, role: GlyphRole.line, solid: true),
    GlyphCircle(8.8, 16.8, 2.6, role: GlyphRole.line, solid: true),
  ]);

  static const search = Glyph([
    GlyphCircle(10.8, 10.8, 6.4, role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(15.6, 15.6), GlyphVertex(20.4, 20.4)], role: GlyphRole.line),
  ]);

  static const bolt = Glyph([
    GlyphPolyline([
      GlyphVertex(13.4, 3.6),
      GlyphVertex(6.6, 13.6, 1),
      GlyphVertex(11.4, 13.6),
      GlyphVertex(10.6, 20.4),
      GlyphVertex(17.4, 10.4, 1),
      GlyphVertex(12.6, 10.4),
    ], closed: true, role: GlyphRole.line),
  ]);

  static const relay = Glyph([
    GlyphPolyline([GlyphVertex(4, 8.4), GlyphVertex(18.5, 8.4)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(15, 5), GlyphVertex(18.8, 8.4, 0.8), GlyphVertex(15, 11.8)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(20, 15.6), GlyphVertex(5.5, 15.6)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(9, 12.2), GlyphVertex(5.2, 15.6, 0.8), GlyphVertex(9, 19)], role: GlyphRole.line),
  ]);

  static const terminal = Glyph([
    GlyphBox(3.4, 4.4, 20.6, 19.6, 3, role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(7.4, 9.6), GlyphVertex(10.4, 12, 0.6), GlyphVertex(7.4, 14.4)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(12.6, 14.8), GlyphVertex(16.6, 14.8)], role: GlyphRole.line),
  ]);

  static const globe = Glyph([
    GlyphCircle(12, 12, 8.6, role: GlyphRole.line),
    GlyphOval(7.4, 3.4, 16.6, 20.6, role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(3.4, 12), GlyphVertex(20.6, 12)], role: GlyphRole.line),
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
    GlyphPolyline([GlyphVertex(12, 4.6), GlyphVertex(12, 19.4)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(4.6, 12), GlyphVertex(19.4, 12)], role: GlyphRole.line),
  ]);

  static const radar = Glyph([
    GlyphCircle(12, 12, 8.6, role: GlyphRole.line),
    GlyphCircle(12, 12, 4.2, role: GlyphRole.line),
    GlyphCircle(12, 12, 0.9, role: GlyphRole.line, solid: true),
    GlyphPolyline([GlyphVertex(12, 12), GlyphVertex(18.4, 7.2)], role: GlyphRole.line),
  ]);

  static const arrowDown = Glyph([
    GlyphPolyline([GlyphVertex(12, 5), GlyphVertex(12, 19)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(6.4, 13.4), GlyphVertex(12, 19.4, 0.8), GlyphVertex(17.6, 13.4)], role: GlyphRole.line),
  ]);

  static const arrowUp = Glyph([
    GlyphPolyline([GlyphVertex(12, 19), GlyphVertex(12, 5)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(6.4, 10.6), GlyphVertex(12, 4.6, 0.8), GlyphVertex(17.6, 10.6)], role: GlyphRole.line),
  ]);

  static const sun = Glyph([
    GlyphCircle(12, 12, 4.4, role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(12, 3.2), GlyphVertex(12, 5) ], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(12, 19), GlyphVertex(12, 20.8)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(3.2, 12), GlyphVertex(5, 12)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(19, 12), GlyphVertex(20.8, 12)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(5.8, 5.8), GlyphVertex(7.1, 7.1)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(16.9, 16.9), GlyphVertex(18.2, 18.2)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(18.2, 5.8), GlyphVertex(16.9, 7.1)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(7.1, 16.9), GlyphVertex(5.8, 18.2)], role: GlyphRole.line),
  ]);

  static const laptop = Glyph([
    GlyphBox(5.2, 5, 18.8, 15, 2, role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(3.4, 18.6), GlyphVertex(20.6, 18.6)], role: GlyphRole.line),
  ]);

  static const monitor = Glyph([
    GlyphBox(3.8, 5, 20.2, 16, 2.2, role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(12, 16), GlyphVertex(12, 19.4)], role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(8.4, 19.4), GlyphVertex(15.6, 19.4)], role: GlyphRole.line),
  ]);

  static const phone = Glyph([
    GlyphBox(7, 3.4, 17, 20.6, 3, role: GlyphRole.line),
    GlyphPolyline([GlyphVertex(10.6, 17.6), GlyphVertex(13.4, 17.6)], role: GlyphRole.line),
  ]);
}
