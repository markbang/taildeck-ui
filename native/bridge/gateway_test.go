package tsbridge

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
	"time"
)

// A NAS file server behind the gateway: Range must come back as 206 with the
// upstream's Content-Range and Content-Type, on the label host (gateway URL)
// and on the forward proxy (the WebView's proxy override).
func TestGatewayPassesRange(t *testing.T) {
	body := bytes.Repeat([]byte("0123456789"), 100000)
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "video/mp4")
		http.ServeContent(w, r, "v.mp4", time.Unix(0, 0), bytes.NewReader(body))
	}))
	defer up.Close()
	gw := testGateway(t)
	_, upPort, _ := net.SplitHostPort(up.Listener.Addr().String())

	label, _ := http.NewRequest("GET", gw.URL+"/d/v.mp4", nil)
	label.Host = fmt.Sprintf("127-0-0-1-%s.localhost", upPort)
	proxied := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(mustURL(t, gw.URL))}}
	forward, _ := http.NewRequest("GET", up.URL+"/d/v.mp4", nil)

	for name, c := range map[string]struct {
		client *http.Client
		req    *http.Request
	}{"label": {http.DefaultClient, label}, "forward": {proxied, forward}} {
		c.req.Header.Set("Range", "bytes=500000-501023")
		resp, err := c.client.Do(c.req)
		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		got, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusPartialContent ||
			resp.Header.Get("Content-Range") != "bytes 500000-501023/1000000" ||
			resp.Header.Get("Content-Type") != "video/mp4" ||
			!bytes.Equal(got, body[500000:501024]) {
			t.Fatalf("%s: %d %v, %d bytes", name, resp.StatusCode, resp.Header, len(got))
		}
	}
}

// A long response streams: the first bytes reach the client while the
// upstream is still writing.
func TestGatewayStreams(t *testing.T) {
	release := make(chan struct{})
	up := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "video/mp4")
		w.Write(make([]byte, 64<<10))
		w.(http.Flusher).Flush()
		<-release
	}))
	defer up.Close()
	defer close(release)
	gw := testGateway(t)
	_, upPort, _ := net.SplitHostPort(up.Listener.Addr().String())
	req, _ := http.NewRequest("GET", gw.URL+"/big.mp4", nil)
	req.Host = fmt.Sprintf("127-0-0-1-%s.localhost", upPort)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	resp, err := http.DefaultClient.Do(req.WithContext(ctx))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if _, err := io.ReadFull(resp.Body, make([]byte, 64<<10)); err != nil {
		t.Fatalf("the first 64 KiB did not stream: %v", err)
	}
}

func testGateway(t *testing.T) *httptest.Server {
	g := &gateway{}
	g.setup(func(ctx context.Context, addr string) (net.Conn, error) {
		var d net.Dialer
		return d.DialContext(ctx, "tcp", addr)
	})
	srv := httptest.NewServer(g)
	t.Cleanup(srv.Close)
	return srv
}

func mustURL(t *testing.T, raw string) *url.URL {
	u, err := url.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	return u
}
