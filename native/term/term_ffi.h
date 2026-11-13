// Plain C ABI for libghostty-vt, for hosts that are not the Android JNI app
// (Flutter via dart:ffi, desktop, iOS). Same state and semantics as term_jni.c.
#ifndef TAILDECK_TERM_FFI_H
#define TAILDECK_TERM_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TdTerm TdTerm;

// fg/bg/cur are 0xRRGGBB. Returns NULL on failure.
TdTerm* td_term_create(int cols, int rows, int scrollback, int fg, int bg, int cur);
void td_term_destroy(TdTerm* t);

// Returned buffers are malloc'd and owned by the caller: free with td_term_free.
// *out_len is 0 and the result NULL when there is nothing to return.
uint8_t* td_term_write(TdTerm* t, const uint8_t* data, size_t len, size_t* out_len);
uint8_t* td_term_resize(TdTerm* t, int cols, int rows, int cw, int ch, size_t* out_len);
uint8_t* td_term_take_clipboard(TdTerm* t, size_t* out_len);
uint8_t* td_term_encode_paste(TdTerm* t, const uint8_t* data, size_t len, size_t* out_len);
uint8_t* td_term_selection_text(TdTerm* t, size_t* out_len);
uint8_t* td_term_title(TdTerm* t, size_t* out_len);

void td_term_scroll(TdTerm* t, int delta);

// Fills cells (4 ints per cell: codepoint, fg, bg, flags) for the whole
// viewport and meta[16]; extra holds multi-codepoint graphemes as
// [cellIndex, len, cp...]. Returns the number of ints written to extra.
//
// meta: 0 cols, 1 rows, 2 cursor visible, 3 cursor x, 4 cursor y,
// 5 cursor style, 6 fg, 7 bg, 8 cursor color, 9 scrollbar total,
// 10 scrollbar offset, 11 scrollbar len, 12 title changed, 13 mouse tracking,
// 14 alternate screen, 15 bit0 bell | bit1 clipboard pending.
int td_term_snapshot(TdTerm* t, int* cells, int cells_cap, int* meta, int* extra, int extra_cap);

// key is a GhosttyKey code (GHOSTTY_KEY_* in ghostty/vt/key.h); mods is a
// GhosttyMods bitmask. text may be NULL.
uint8_t* td_term_encode_key(TdTerm* t, int key, int mods, const char* text, int text_len,
                            uint32_t unshifted, size_t* out_len);

// action: 0 press, 1 release, 2 motion. button: 0 none, 1 left, 4/5 wheel up/down.
uint8_t* td_term_encode_mouse(TdTerm* t, int action, int button, int pressed, float x, float y,
                              int w, int h, int cw, int ch, size_t* out_len);

uint8_t* td_term_encode_focus(TdTerm* t, int gained, size_t* out_len);

// Selects cells between two viewport positions (inclusive); x0 < 0 clears.
void td_term_select(TdTerm* t, int x0, int y0, int x1, int y1);

// Display width (0, 1 or 2 cells) per Ghostty's Unicode tables.
int td_term_codepoint_width(uint32_t cp);

void td_term_free(void* p);

#ifdef __cplusplus
}
#endif

#endif
