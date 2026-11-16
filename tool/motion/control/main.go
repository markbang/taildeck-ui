// motion_control runs Tailscale's test control plane with three changes the
// recording needs: every peer is reported online (testcontrol leaves that to a
// test that flips nodes' state, and both apps gate their Scan button on it),
// the relay map points at 127.0.0.1, which the recording script reverses into
// the emulator, and -hold-map delays the first netmap so the app meets the
// window where the node is Running but has no peers yet.
package main

import (
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"sync"
	"testing"
	"time"

	"tailscale.com/tailcfg"
	"tailscale.com/tstest/integration"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8080", "IP:port to listen on; the DERP and STUN servers run on that IP too")
	fake := flag.Int("nfake", 0, "number of fake nodes to add")
	hold := flag.Duration("hold-map", 0, "delay the first netmap by this much (a cold start on a slow tailnet)")
	flag.Parse()

	host, _, err := net.SplitHostPort(*addr)
	if err != nil {
		log.Fatalf("invalid --addr %q: %v", *addr, err)
	}
	var t fakeTB
	derpMap := integration.RunDERPAndSTUN(t, logger.Discard, host)
	control := &testcontrol.Server{
		DERPMap:         derpMap,
		ExplicitBaseURL: "http://" + *addr,
		AllOnline:       true,
	}
	for range *fake {
		control.AddFakeNode()
	}
	// Holding the first netmap needs a start marker: POST /__hold arms a
	// window that opens at the next map request, so every cold start of the
	// app under test meets the same delay instead of only the first one.
	var holdMu sync.Mutex
	var armed bool
	var windowStart time.Time
	if *hold > 0 {
		control.HoldMapRequest = func(*tailcfg.MapRequest) func() {
			holdMu.Lock()
			wait := time.Duration(0)
			if armed {
				if windowStart.IsZero() {
					windowStart = time.Now()
				}
				wait = time.Until(windowStart.Add(*hold))
				if wait <= 0 {
					armed = false
				}
			}
			holdMu.Unlock()
			if wait > 0 {
				time.Sleep(wait)
			}
			return nil
		}
		log.Printf("holding each armed start's first netmap for %s", *hold)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/__hold", func(w http.ResponseWriter, r *http.Request) {
		holdMu.Lock()
		armed = *hold > 0
		windowStart = time.Time{}
		holdMu.Unlock()
		fmt.Fprintf(w, "armed %s\n", *hold)
	})
	mux.Handle("/", control)
	log.Printf("listening on %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, mux))
}

type fakeTB struct{ *testing.T }

func (t fakeTB) Cleanup(_ func())               {}
func (t fakeTB) Error(args ...any)              { t.Fatal(args...) }
func (t fakeTB) Errorf(format string, a ...any) { t.Fatalf(format, a...) }
func (t fakeTB) Fail()                          { t.Fatal("failed") }
func (t fakeTB) FailNow()                       { t.Fatal("failed") }
func (t fakeTB) Failed() bool                   { return false }
func (t fakeTB) Fatal(args ...any)              { log.Fatal(args...) }
func (t fakeTB) Fatalf(format string, a ...any) { log.Fatalf(format, a...) }
func (t fakeTB) Helper()                        {}
func (t fakeTB) Log(args ...any)                { log.Print(args...) }
func (t fakeTB) Logf(format string, a ...any)   { log.Printf(format, a...) }
func (t fakeTB) Name() string                   { return "faketest" }
func (t fakeTB) Setenv(string, string)          { panic("not implemented") }
func (t fakeTB) Skip(args ...any)               { t.Fatal("skipped") }
func (t fakeTB) SkipNow()                       { t.Fatal("skipnow") }
func (t fakeTB) Skipf(string, ...any)           { t.Fatal("skipped") }
func (t fakeTB) Skipped() bool                  { return false }
func (t fakeTB) TempDir() string                { panic("not implemented") }
