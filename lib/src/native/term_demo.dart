import 'dart:convert';
import 'dart:typed_data';

/// Canned ANSI session for `?ssh=demo`: styles, 16 colors and truecolor, a
/// wide CJK block, a scrolled-away region and a cursor, all through
/// `td_term_write`. There is no SSH here; the next milestone plugs a session
/// into the same emulator.
Uint8List demoSessionBytes({int rows = 24}) {
  final b = StringBuffer();
  b.write('\x1b]0;devbox — taildeck\x07');
  b.write('\x1b[2J\x1b[H');
  final filler = rows + 16;
  for (var i = 1; i <= filler; i++) {
    b.write('\x1b[2m  boot [$i/$filler] tailscale0 up · derp nyc3 · handshake ok\x1b[0m\r\n');
  }
  b.write('\r\n');
  b.write('\x1b[1;32mdevbox\x1b[0m:\x1b[1;34m~\x1b[0m\$ \x1b[1m./styles --colors 8\x1b[0m\r\n');
  b.write('  \x1b[1mbold\x1b[0m   \x1b[3mitalic\x1b[0m   \x1b[4munderline\x1b[0m   \x1b[9mstrike\x1b[0m   \x1b[7minverse\x1b[0m\r\n');
  b.write('  \x1b[31mred\x1b[0m  \x1b[32mgreen\x1b[0m  \x1b[33myellow\x1b[0m  \x1b[34mblue\x1b[0m  \x1b[35mmagenta\x1b[0m  \x1b[36mcyan\x1b[0m\r\n');
  b.write('  \x1b[38;2;255;153;51mtruecolor #FF9933\x1b[0m  \x1b[41m red bg \x1b[0m \x1b[42m green bg \x1b[0m \x1b[44m blue bg \x1b[0m\r\n');
  b.write('\x1b[1;32mdevbox\x1b[0m:\x1b[1;34m~\x1b[0m\$ \x1b[1m./cjk\x1b[0m\r\n');
  b.write('  \x1b[1m全角中文\x1b[0m  日本語  ハングル  ＦＵＬＬ　ＷＩＤＴＨ\r\n');
  b.write('\x1b[2m  双倍宽度字形：汉字、假名与全角标点，各占两个单元格。\x1b[0m\r\n');
  b.write('\x1b[1;32mdevbox\x1b[0m:\x1b[1;34m~\x1b[0m\$ ');
  return Uint8List.fromList(utf8.encode(b.toString()));
}
