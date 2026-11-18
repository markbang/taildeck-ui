package main

import (
	"bytes"
	"embed"
	"fmt"
	"html"
	"log"
	"net/http"
	"path"
	"strings"
	"time"
)

// The video gate's clips: 8 s of testsrc with a tone, as H.264/AAC mp4, the
// same split into an HLS playlist, and H.265/AAC mp4.
//
//go:embed media
var media embed.FS

var mediaTypes = map[string]string{
	".mp4":  "video/mp4",
	".m3u8": "application/vnd.apple.mpegurl",
	".ts":   "video/mp2t",
}

// serveMedia answers Range requests with 206 like a NAS file server does.
func serveMedia(w http.ResponseWriter, r *http.Request) {
	name := path.Base(r.URL.Path)
	data, err := media.ReadFile("media/" + name)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	log.Printf("media %s range=%q", name, r.Header.Get("Range"))
	if t, ok := mediaTypes[path.Ext(name)]; ok {
		w.Header().Set("Content-Type", t)
	}
	http.ServeContent(w, r, name, time.Unix(0, 0), bytes.NewReader(data))
}

// videoPage plays each clip muted and reports per clip to /report. The
// absolute source is built from the Host the server saw, the way AList and
// OpenList build raw_url: behind the gateway that is the tailnet name.
func videoPage(w http.ResponseWriter, r *http.Request) {
	abs := "http://" + r.Host + "/media/h264.mp4"
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	fmt.Fprintf(w, videoHTML, html.EscapeString(abs))
}

func videoReport(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	fields := []string{}
	for _, k := range []string{"case", "ok", "t", "err", "can", "origin"} {
		fields = append(fields, k+"="+strings.ReplaceAll(q.Get(k), " ", "_"))
	}
	log.Printf("video-report %s", strings.Join(fields, " "))
	w.WriteHeader(http.StatusNoContent)
}

const videoHTML = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<title>video gate</title>
<style>
body{font-family:system-ui;background:#101214;color:#e8eaed;margin:0;padding:12px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
video{width:100%%;aspect-ratio:16/9;background:#000}
p{margin:4px 0 0;font:13px monospace;word-break:break-all}
</style>
<div class="grid">
<div><video data-case="h264-rel" src="/media/h264.mp4"></video><p></p></div>
<div><video data-case="h264-abs" src="%s"></video><p></p></div>
<div><video data-case="hls" src="/media/hls.m3u8"></video><p></p></div>
<div><video data-case="hevc" src="/media/hevc.mp4"></video><p></p></div>
</div>
<p id="origin"></p>
<script>
document.getElementById('origin').textContent = location.origin;
for (const v of document.querySelectorAll('video')) {
  const name = v.dataset.case, line = v.nextElementSibling;
  const can = v.canPlayType(name === 'hls' ? 'application/vnd.apple.mpegurl'
    : name === 'hevc' ? 'video/mp4; codecs="hvc1"' : 'video/mp4; codecs="avc1.42E01E"');
  let done = false, best = 0;
  const report = (ok, err) => {
    if (done) return;
    done = true;
    const q = new URLSearchParams({case: name, ok: ok ? '1' : '0', t: best.toFixed(2),
      err: err || '', can: can || 'no', origin: location.origin});
    line.textContent = name + ': ' + (ok ? 'PLAYING ' + best.toFixed(1) + 's' : 'FAILED ' + err);
    console.log('video-report ' + q.toString());
    fetch('/report?' + q.toString()).catch(() => {});
  };
  line.textContent = name + ': loading (canPlayType ' + (can || 'no') + ')';
  v.muted = true; v.loop = true; v.playsInline = true;
  v.addEventListener('timeupdate', () => {
    best = Math.max(best, v.currentTime);
    if (best > 1.5) report(true);
  });
  v.addEventListener('error', () => {
    const e = v.error;
    report(false, 'code' + (e ? e.code : '?') + ':' + (e && e.message ? e.message : ''));
  });
  v.play().catch(e => line.textContent += ' play(): ' + e.name);
  setTimeout(() => report(false, 'timeout:readyState' + v.readyState + ':networkState' + v.networkState), 30000);
}
</script>`
