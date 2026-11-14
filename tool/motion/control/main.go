// motion_control runs Tailscale's test control plane with two changes the
// recording needs: every peer is reported online (testcontrol leaves that to a
// test that flips nodes' state, and both apps gate their Scan button on it),
// and the relay map points at 127.0.0.1, which the recording script reverses
// into the emulator.
package main

import (
	"flag"
	"log"
	"net"
	"net/http"
	"testing"

	"tailscale.com/tstest/integration"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:8080", "IP:port to listen on; the DERP and STUN servers run on that IP too")
	fake := flag.Int("nfake", 0, "number of fake nodes to add")
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
	mux := http.NewServeMux()
	mux.Handle("/", control)
	log.Printf("listening on %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, mux))
}

type fakeTB struct{ *testing.T }

func (t fakeTB) Cleanup(_ func())                {}
func (t fakeTB) Error(args ...any)               { t.Fatal(args...) }
func (t fakeTB) Errorf(format string, a ...any)  { t.Fatalf(format, a...) }
func (t fakeTB) Fail()                           { t.Fatal("failed") }
func (t fakeTB) FailNow()                        { t.Fatal("failed") }
func (t fakeTB) Failed() bool                    { return false }
func (t fakeTB) Fatal(args ...any)               { log.Fatal(args...) }
func (t fakeTB) Fatalf(format string, a ...any)  { log.Fatalf(format, a...) }
func (t fakeTB) Helper()                         {}
func (t fakeTB) Log(args ...any)                 { log.Print(args...) }
func (t fakeTB) Logf(format string, a ...any)    { log.Printf(format, a...) }
func (t fakeTB) Name() string                    { return "faketest" }
func (t fakeTB) Setenv(string, string)           { panic("not implemented") }
func (t fakeTB) Skip(args ...any)                { t.Fatal("skipped") }
func (t fakeTB) SkipNow()                        { t.Fatal("skipnow") }
func (t fakeTB) Skipf(string, ...any)            { t.Fatal("skipped") }
func (t fakeTB) Skipped() bool                   { return false }
func (t fakeTB) TempDir() string                 { panic("not implemented") }
