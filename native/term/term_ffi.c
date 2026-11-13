// Plain C ABI for libghostty-vt (see term_ffi.h). Same Term state and
// callbacks as term_jni.c, without JNI so Flutter, desktop and iOS can use it.
// Every entry point takes the per-terminal mutex: output arrives on a network
// thread while rendering and input happen on the UI thread.

#include "term_ffi.h"

#include <stdlib.h>
#include <string.h>

#include <ghostty/vt.h>

#if defined(_WIN32)
#include <windows.h>
typedef SRWLOCK td_mutex;
static void td_mutex_init(td_mutex* m) { InitializeSRWLock(m); }
static void td_mutex_lock(td_mutex* m) { AcquireSRWLockExclusive(m); }
static void td_mutex_unlock(td_mutex* m) { ReleaseSRWLockExclusive(m); }
static void td_mutex_destroy(td_mutex* m) { (void)m; }
#else
#include <pthread.h>
typedef pthread_mutex_t td_mutex;
static void td_mutex_init(td_mutex* m) { pthread_mutex_init(m, NULL); }
static void td_mutex_lock(td_mutex* m) { pthread_mutex_lock(m); }
static void td_mutex_unlock(td_mutex* m) { pthread_mutex_unlock(m); }
static void td_mutex_destroy(td_mutex* m) { pthread_mutex_destroy(m); }
#endif

struct TdTerm {
  GhosttyTerminal term;
  GhosttyRenderState rs;
  GhosttyRenderStateRowIterator rows;
  GhosttyRenderStateRowCells cells;
  GhosttyKeyEncoder keys;
  GhosttyKeyEvent key_event;
  GhosttyMouseEncoder mouse;
  GhosttyMouseEvent mouse_event;
  td_mutex mu;
  // Responses the terminal wants sent back to the remote (DA, DSR, ...).
  uint8_t* out;
  size_t out_len;
  size_t out_cap;
  int title_changed;
  int bell;
  // Latest OSC 52 clipboard write, handed to the host after a write.
  uint8_t* clip;
  size_t clip_len;
  int clip_pending;
};

static void out_append(TdTerm* t, const uint8_t* data, size_t len) {
  if (t->out_len + len > t->out_cap) {
    size_t cap = t->out_cap ? t->out_cap * 2 : 256;
    while (cap < t->out_len + len) cap *= 2;
    uint8_t* p = realloc(t->out, cap);
    if (!p) return;
    t->out = p;
    t->out_cap = cap;
  }
  memcpy(t->out + t->out_len, data, len);
  t->out_len += len;
}

// Takes ownership of the pending response bytes.
static uint8_t* take_out(TdTerm* t, size_t* out_len) {
  uint8_t* p = t->out;
  size_t n = t->out_len;
  t->out = NULL;
  t->out_len = 0;
  t->out_cap = 0;
  *out_len = n;
  return n ? p : (free(p), NULL);
}

static uint8_t* dup_bytes(const uint8_t* buf, size_t len, size_t* out_len) {
  *out_len = 0;
  if (len == 0) return NULL;
  uint8_t* p = malloc(len);
  if (!p) return NULL;
  memcpy(p, buf, len);
  *out_len = len;
  return p;
}

static void on_write_pty(GhosttyTerminal term, void* ud, const uint8_t* data, size_t len) {
  (void)term;
  out_append((TdTerm*)ud, data, len);
}

static void on_title(GhosttyTerminal term, void* ud) {
  (void)term;
  ((TdTerm*)ud)->title_changed = 1;
}

static void on_bell(GhosttyTerminal term, void* ud) {
  (void)term;
  ((TdTerm*)ud)->bell = 1;
}

static void on_clipboard_write(GhosttyTerminal term, void* ud, const GhosttyClipboardWrite* w) {
  (void)term;
  TdTerm* t = (TdTerm*)ud;
  GhosttyClipboardWriteReply reply = {.size = sizeof(reply), .result = GHOSTTY_CLIPBOARD_WRITE_RESULT_SUCCESS, .remember = false};
  const GhosttyClipboardContent* text = NULL;
  for (size_t i = 0; i < w->contents_len; i++) {
    const GhosttyClipboardContent* c = &w->contents[i];
    if (c->mime.len == 0 || (c->mime.len >= 4 && memcmp(c->mime.ptr, "text", 4) == 0)) {
      text = c;
      break;
    }
  }
  // Phones have one clipboard; selection/primary writes land there too.
  if (text) {
    uint8_t* p = realloc(t->clip, text->data.len + 1);
    if (p) {
      memcpy(p, text->data.ptr, text->data.len);
      t->clip = p;
      t->clip_len = text->data.len;
      t->clip_pending = 1;
    }
  } else {
    reply.result = GHOSTTY_CLIPBOARD_WRITE_RESULT_UNSUPPORTED;
  }
  w->reply(w, &reply);
}

static GhosttyColorRgb to_rgb(int c) {
  return (GhosttyColorRgb){.r = (uint8_t)(c >> 16), .g = (uint8_t)(c >> 8), .b = (uint8_t)c};
}

TdTerm* td_term_create(int cols, int rows, int scrollback, int fg, int bg, int cur) {
  TdTerm* t = calloc(1, sizeof(TdTerm));
  if (!t) return NULL;
  if (ghostty_terminal_new(NULL, &t->term, (uint16_t)cols, (uint16_t)rows) != GHOSTTY_SUCCESS) {
    free(t);
    return NULL;
  }
  ghostty_render_state_new(NULL, &t->rs);
  ghostty_render_state_row_iterator_new(NULL, &t->rows);
  ghostty_render_state_row_cells_new(NULL, &t->cells);
  ghostty_key_encoder_new(NULL, &t->keys);
  ghostty_key_event_new(NULL, &t->key_event);
  ghostty_mouse_encoder_new(NULL, &t->mouse);
  ghostty_mouse_event_new(NULL, &t->mouse_event);
  td_mutex_init(&t->mu);

  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_USERDATA, t);
  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_WRITE_PTY, (const void*)on_write_pty);
  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_TITLE_CHANGED, (const void*)on_title);
  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_BELL, (const void*)on_bell);
  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE, (const void*)on_clipboard_write);
  size_t lines = (size_t)scrollback;
  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_SCROLLBACK_MAX_LINES, &lines);
  GhosttyColorRgb cfg = to_rgb(fg), cbg = to_rgb(bg), ccur = to_rgb(cur);
  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_COLOR_FOREGROUND, &cfg);
  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_COLOR_BACKGROUND, &cbg);
  ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_COLOR_CURSOR, &ccur);
  return t;
}

void td_term_destroy(TdTerm* t) {
  if (!t) return;
  td_mutex_lock(&t->mu);
  ghostty_mouse_event_free(t->mouse_event);
  ghostty_mouse_encoder_free(t->mouse);
  ghostty_key_event_free(t->key_event);
  ghostty_key_encoder_free(t->keys);
  ghostty_render_state_row_cells_free(t->cells);
  ghostty_render_state_row_iterator_free(t->rows);
  ghostty_render_state_free(t->rs);
  ghostty_terminal_free(t->term);
  free(t->out);
  free(t->clip);
  td_mutex_unlock(&t->mu);
  td_mutex_destroy(&t->mu);
  free(t);
}

// Feeds remote output and returns any response bytes to send back.
uint8_t* td_term_write(TdTerm* t, const uint8_t* data, size_t len, size_t* out_len) {
  *out_len = 0;
  if (!t || (!data && len)) return NULL;
  td_mutex_lock(&t->mu);
  ghostty_terminal_vt_write(t->term, data, len);
  uint8_t* out = take_out(t, out_len);
  td_mutex_unlock(&t->mu);
  return out;
}

uint8_t* td_term_resize(TdTerm* t, int cols, int rows, int cw, int ch, size_t* out_len) {
  *out_len = 0;
  if (!t) return NULL;
  td_mutex_lock(&t->mu);
  ghostty_terminal_resize(t->term, (uint16_t)cols, (uint16_t)rows, (uint32_t)cw, (uint32_t)ch);
  uint8_t* out = take_out(t, out_len);
  td_mutex_unlock(&t->mu);
  return out;
}

void td_term_scroll(TdTerm* t, int delta) {
  if (!t) return;
  GhosttyTerminalScrollViewport s = {0};
  if (delta == 0) {
    s.tag = GHOSTTY_SCROLL_VIEWPORT_BOTTOM;
  } else {
    s.tag = GHOSTTY_SCROLL_VIEWPORT_DELTA;
    s.value.delta = delta;
  }
  td_mutex_lock(&t->mu);
  ghostty_terminal_scroll_viewport(t->term, s);
  td_mutex_unlock(&t->mu);
}

// Bits for the per-cell flags word in td_term_snapshot().
enum {
  F_BOLD = 1 << 0,
  F_ITALIC = 1 << 1,
  F_FAINT = 1 << 2,
  F_UNDERLINE = 1 << 3,
  F_STRIKE = 1 << 4,
  F_INVERSE = 1 << 5,
  F_INVISIBLE = 1 << 6,
  F_WIDE = 1 << 7,
  F_SPACER = 1 << 8,
  F_SELECTED = 1 << 9,
  F_HAS_FG = 1 << 10,
  F_HAS_BG = 1 << 11,
  F_MULTI = 1 << 12,
};

static int rgb(GhosttyColorRgb c) { return (int)(0xFF000000u | ((uint32_t)c.r << 16) | ((uint32_t)c.g << 8) | c.b); }

int td_term_snapshot(TdTerm* t, int* cells, int cells_cap, int* meta, int* extra, int extra_cap) {
  if (!t || !cells || !meta) return 0;
  int extra_len = 0;
  memset(meta, 0, 16 * sizeof(int));

  td_mutex_lock(&t->mu);
  ghostty_render_state_update(t->rs, t->term);

  uint16_t cols = 0, nrows = 0;
  ghostty_render_state_get(t->rs, GHOSTTY_RENDER_STATE_DATA_COLS, &cols);
  ghostty_render_state_get(t->rs, GHOSTTY_RENDER_STATE_DATA_ROWS, &nrows);
  GhosttyRenderStateColors colors = GHOSTTY_INIT_SIZED(GhosttyRenderStateColors);
  ghostty_render_state_get(t->rs, GHOSTTY_RENDER_STATE_DATA_COLORS, &colors);
  GhosttyRenderStateCursor cursor = GHOSTTY_INIT_SIZED(GhosttyRenderStateCursor);
  ghostty_render_state_get(t->rs, GHOSTTY_RENDER_STATE_DATA_CURSOR, &cursor);

  meta[0] = cols;
  meta[1] = nrows;
  meta[2] = cursor.visible && cursor.viewport_has_value;
  meta[3] = cursor.viewport_x;
  meta[4] = cursor.viewport_y;
  meta[5] = (int)cursor.visual_style;
  meta[6] = rgb(colors.foreground);
  meta[7] = rgb(colors.background);
  meta[8] = colors.cursor_has_value ? rgb(colors.cursor) : 0;
  GhosttyTerminalScrollbar sb = {0};
  if (ghostty_terminal_get(t->term, GHOSTTY_TERMINAL_DATA_SCROLLBAR, &sb) == GHOSTTY_SUCCESS) {
    meta[9] = (int)sb.total;
    meta[10] = (int)sb.offset;
    meta[11] = (int)sb.len;
  }
  meta[12] = t->title_changed;
  t->title_changed = 0;
  bool tracking = false;
  ghostty_terminal_get(t->term, GHOSTTY_TERMINAL_DATA_MOUSE_TRACKING, &tracking);
  meta[13] = tracking;
  GhosttyTerminalScreen screen = GHOSTTY_TERMINAL_SCREEN_PRIMARY;
  ghostty_terminal_get(t->term, GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN, &screen);
  meta[14] = screen == GHOSTTY_TERMINAL_SCREEN_ALTERNATE;
  meta[15] = (t->bell ? 1 : 0) | (t->clip_pending ? 2 : 0);
  t->bell = 0;

  ghostty_render_state_get(t->rs, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &t->rows);
  int y = 0;
  while (y < nrows && ghostty_render_state_row_iterator_next(t->rows)) {
    ghostty_render_state_row_get(t->rows, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &t->cells);
    int x = 0;
    while (x < cols && ghostty_render_state_row_cells_next(t->cells)) {
      int idx = y * cols + x;
      if ((idx + 1) * 4 > cells_cap) break;
      int* c = cells + idx * 4;
      uint32_t glen = 0;
      ghostty_render_state_row_cells_get(t->cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_LEN, &glen);
      uint32_t cps[16] = {0};
      if (glen > 0) ghostty_render_state_row_cells_get(t->cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_GRAPHEMES_BUF, cps);
      GhosttyStyle style = GHOSTTY_INIT_SIZED(GhosttyStyle);
      ghostty_render_state_row_cells_get(t->cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style);
      int flags = 0;
      GhosttyColorRgb fg, bg;
      if (ghostty_render_state_row_cells_get(t->cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_FG_COLOR, &fg) == GHOSTTY_SUCCESS) {
        flags |= F_HAS_FG;
        c[1] = rgb(fg);
      } else {
        c[1] = 0;
      }
      if (ghostty_render_state_row_cells_get(t->cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_BG_COLOR, &bg) == GHOSTTY_SUCCESS) {
        flags |= F_HAS_BG;
        c[2] = rgb(bg);
      } else {
        c[2] = 0;
      }
      if (style.bold) flags |= F_BOLD;
      if (style.italic) flags |= F_ITALIC;
      if (style.faint) flags |= F_FAINT;
      if (style.underline != 0) flags |= F_UNDERLINE;
      if (style.strikethrough) flags |= F_STRIKE;
      if (style.inverse) flags |= F_INVERSE;
      if (style.invisible) flags |= F_INVISIBLE;
      bool selected = false;
      ghostty_render_state_row_cells_get(t->cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_SELECTED, &selected);
      if (selected) flags |= F_SELECTED;
      GhosttyCell raw = 0;
      if (ghostty_render_state_row_cells_get(t->cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &raw) == GHOSTTY_SUCCESS) {
        GhosttyCellWide wide = GHOSTTY_CELL_WIDE_NARROW;
        ghostty_cell_get(raw, GHOSTTY_CELL_DATA_WIDE, &wide);
        if (wide == GHOSTTY_CELL_WIDE_WIDE) flags |= F_WIDE;
        if (wide == GHOSTTY_CELL_WIDE_SPACER_TAIL || wide == GHOSTTY_CELL_WIDE_SPACER_HEAD) flags |= F_SPACER;
      }
      c[0] = glen > 0 ? (int)cps[0] : 0;
      if (glen > 1) {
        uint32_t n = glen < 16 ? glen : 16;
        if (extra && extra_len + 2 + (int)n <= extra_cap) {
          flags |= F_MULTI;
          extra[extra_len++] = idx;
          extra[extra_len++] = (int)n;
          for (uint32_t i = 0; i < n; i++) extra[extra_len++] = (int)cps[i];
        }
      }
      c[3] = flags;
      x++;
    }
    for (; x < cols; x++) {
      int idx = y * cols + x;
      if ((idx + 1) * 4 > cells_cap) break;
      memset(cells + idx * 4, 0, 4 * sizeof(int));
    }
    y++;
  }
  ghostty_render_state_clean(t->rs);
  td_mutex_unlock(&t->mu);
  return extra_len;
}

// Encodes a key press honoring terminal modes (cursor-key mode, kitty
// keyboard protocol, ...). key is a GhosttyKey; returns NULL if it has no
// encoding.
uint8_t* td_term_encode_key(TdTerm* t, int key, int mods, const char* text, int text_len,
                            uint32_t unshifted, size_t* out_len) {
  *out_len = 0;
  if (!t) return NULL;
  if (key == GHOSTTY_KEY_UNIDENTIFIED && text == NULL) return NULL;
  char buf[128];
  size_t n = 0;
  td_mutex_lock(&t->mu);
  ghostty_key_encoder_setopt_from_terminal(t->keys, t->term);
  ghostty_key_event_set_action(t->key_event, GHOSTTY_KEY_ACTION_PRESS);
  ghostty_key_event_set_key(t->key_event, (GhosttyKey)key);
  ghostty_key_event_set_mods(t->key_event, (GhosttyMods)mods);
  ghostty_key_event_set_consumed_mods(t->key_event, 0);
  ghostty_key_event_set_composing(t->key_event, false);
  ghostty_key_event_set_utf8(t->key_event, text, text ? (size_t)text_len : 0);
  ghostty_key_event_set_unshifted_codepoint(t->key_event, unshifted);
  GhosttyResult r = ghostty_key_encoder_encode(t->keys, t->key_event, buf, sizeof(buf), &n);
  ghostty_key_event_set_utf8(t->key_event, NULL, 0);
  ghostty_terminal_scroll_viewport(t->term, (GhosttyTerminalScrollViewport){.tag = GHOSTTY_SCROLL_VIEWPORT_BOTTOM});
  td_mutex_unlock(&t->mu);
  return r == GHOSTTY_SUCCESS ? dup_bytes((const uint8_t*)buf, n, out_len) : NULL;
}

// Encodes a mouse event at pixel (x, y) per the remote's tracking mode and
// format. Returns NULL when the remote doesn't want this event.
uint8_t* td_term_encode_mouse(TdTerm* t, int action, int button, int pressed, float x, float y,
                              int w, int h, int cw, int ch, size_t* out_len) {
  *out_len = 0;
  if (!t) return NULL;
  char buf[64];
  size_t n = 0;
  td_mutex_lock(&t->mu);
  ghostty_mouse_encoder_setopt_from_terminal(t->mouse, t->term);
  GhosttyMouseEncoderSize size = GHOSTTY_INIT_SIZED(GhosttyMouseEncoderSize);
  size.screen_width = (uint32_t)w;
  size.screen_height = (uint32_t)h;
  size.cell_width = (uint32_t)cw;
  size.cell_height = (uint32_t)ch;
  ghostty_mouse_encoder_setopt(t->mouse, GHOSTTY_MOUSE_ENCODER_OPT_SIZE, &size);
  bool any = pressed != 0;
  ghostty_mouse_encoder_setopt(t->mouse, GHOSTTY_MOUSE_ENCODER_OPT_ANY_BUTTON_PRESSED, &any);
  ghostty_mouse_event_set_action(t->mouse_event, (GhosttyMouseAction)action);
  if (button > 0) {
    ghostty_mouse_event_set_button(t->mouse_event, (GhosttyMouseButton)button);
  } else {
    ghostty_mouse_event_clear_button(t->mouse_event);
  }
  ghostty_mouse_event_set_mods(t->mouse_event, 0);
  ghostty_mouse_event_set_position(t->mouse_event, (GhosttyMousePosition){.x = x, .y = y});
  GhosttyResult r = ghostty_mouse_encoder_encode(t->mouse, t->mouse_event, buf, sizeof(buf), &n);
  td_mutex_unlock(&t->mu);
  return r == GHOSTTY_SUCCESS ? dup_bytes((const uint8_t*)buf, n, out_len) : NULL;
}

// Focus in/out report, only when the remote enabled mode 1004.
uint8_t* td_term_encode_focus(TdTerm* t, int gained, size_t* out_len) {
  *out_len = 0;
  if (!t) return NULL;
  bool enabled = false;
  GhosttyTerminalModeConfig mode = {.mode = GHOSTTY_MODE_FOCUS_EVENT};
  td_mutex_lock(&t->mu);
  if (ghostty_terminal_get(t->term, GHOSTTY_TERMINAL_DATA_MODE, &mode) == GHOSTTY_SUCCESS) enabled = mode.value;
  td_mutex_unlock(&t->mu);
  if (!enabled) return NULL;
  char buf[8];
  size_t n = 0;
  if (ghostty_focus_encode(gained ? GHOSTTY_FOCUS_GAINED : GHOSTTY_FOCUS_LOST, buf, sizeof(buf), &n) != GHOSTTY_SUCCESS) return NULL;
  return dup_bytes((const uint8_t*)buf, n, out_len);
}

uint8_t* td_term_take_clipboard(TdTerm* t, size_t* out_len) {
  *out_len = 0;
  if (!t) return NULL;
  uint8_t* out = NULL;
  td_mutex_lock(&t->mu);
  if (t->clip_pending) {
    out = dup_bytes(t->clip, t->clip_len, out_len);
    t->clip_pending = 0;
  }
  td_mutex_unlock(&t->mu);
  return out;
}

// Wraps pasted text in bracketed-paste markers when the remote asked for it.
uint8_t* td_term_encode_paste(TdTerm* t, const uint8_t* data, size_t len, size_t* out_len) {
  *out_len = 0;
  if (!t || (!data && len)) return NULL;
  bool bracketed = false;
  GhosttyTerminalModeConfig mode = {.mode = GHOSTTY_MODE_BRACKETED_PASTE};
  td_mutex_lock(&t->mu);
  if (ghostty_terminal_get(t->term, GHOSTTY_TERMINAL_DATA_MODE, &mode) == GHOSTTY_SUCCESS) bracketed = mode.value;
  td_mutex_unlock(&t->mu);
  size_t cap = len + 16;
  char* buf = malloc(cap);
  if (!buf) return NULL;
  size_t n = 0;
  uint8_t* out = NULL;
  char* text = (char*)data; // the encoder only reads
  if (ghostty_paste_encode(text, len, bracketed, buf, cap, &n) == GHOSTTY_SUCCESS) {
    out = dup_bytes((const uint8_t*)buf, n, out_len);
  }
  free(buf);
  return out;
}

static GhosttyGridRef viewport_ref(TdTerm* t, int x, int y) {
  GhosttyGridRef ref = GHOSTTY_INIT_SIZED(GhosttyGridRef);
  GhosttyPoint pt = {.tag = GHOSTTY_POINT_TAG_VIEWPORT, .value = {.coordinate = {.x = (uint16_t)x, .y = (uint32_t)y}}};
  ghostty_terminal_grid_ref(t->term, pt, &ref);
  return ref;
}

// Selects cells between two viewport positions (inclusive); x0 < 0 clears.
void td_term_select(TdTerm* t, int x0, int y0, int x1, int y1) {
  if (!t) return;
  td_mutex_lock(&t->mu);
  if (x0 < 0) {
    ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_SELECTION, NULL);
  } else {
    GhosttySelection sel = GHOSTTY_INIT_SIZED(GhosttySelection);
    sel.start = viewport_ref(t, x0, y0);
    sel.end = viewport_ref(t, x1, y1);
    ghostty_terminal_set(t->term, GHOSTTY_TERMINAL_OPT_SELECTION, &sel);
  }
  td_mutex_unlock(&t->mu);
}

uint8_t* td_term_selection_text(TdTerm* t, size_t* out_len) {
  *out_len = 0;
  if (!t) return NULL;
  uint8_t* out = NULL;
  td_mutex_lock(&t->mu);
  GhosttySelection sel = GHOSTTY_INIT_SIZED(GhosttySelection);
  if (ghostty_terminal_get(t->term, GHOSTTY_TERMINAL_DATA_SELECTION, &sel) == GHOSTTY_SUCCESS) {
    GhosttyTerminalSelectionFormatOptions opts = GHOSTTY_INIT_SIZED(GhosttyTerminalSelectionFormatOptions);
    opts.emit = GHOSTTY_FORMATTER_FORMAT_PLAIN;
    opts.trim = true;
    opts.selection = &sel;
    uint8_t* buf = NULL;
    size_t len = 0;
    if (ghostty_terminal_selection_format_alloc(t->term, NULL, opts, &buf, &len) == GHOSTTY_SUCCESS) {
      out = dup_bytes(buf, len, out_len);
      ghostty_free(NULL, buf, len);
    }
  }
  td_mutex_unlock(&t->mu);
  return out;
}

uint8_t* td_term_title(TdTerm* t, size_t* out_len) {
  *out_len = 0;
  if (!t) return NULL;
  uint8_t* out = NULL;
  td_mutex_lock(&t->mu);
  GhosttyString title = {0};
  if (ghostty_terminal_get(t->term, GHOSTTY_TERMINAL_DATA_TITLE, &title) == GHOSTTY_SUCCESS) {
    out = dup_bytes((const uint8_t*)title.ptr, title.len, out_len);
  }
  td_mutex_unlock(&t->mu);
  return out;
}

int td_term_codepoint_width(uint32_t cp) { return (int)ghostty_unicode_codepoint_width(cp); }

void td_term_free(void* p) { free(p); }
