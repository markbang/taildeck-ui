// motion_peer joins the recording session's test control plane and serves one
// page on the tailnet, so the apps under test have a real peer to list, ping,
// scan and open: testcontrol's fake nodes are offline and answer nothing.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"time"

	"tailscale.com/tsnet"
)

const page = `<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
<title>motion peer</title>
<body style="font-family:system-ui;background:#101214;color:#e8eaed;padding:28px">
<h1 style="font-size:22px">motion peer</h1>
<p>A tailnet page served by the recording runner.</p>
<button onclick="document.getElementById('n').textContent='clicked'">Press</button>
<p id="n"></p>
</body>`

func main() {
	hostname := flag.String("hostname", "motionpeer", "tailnet hostname")
	control := flag.String("control", "http://127.0.0.1:8080", "control server URL")
	key := flag.String("key", "tskey-test", "auth key")
	port := flag.Int("port", 3000, "tailnet port to serve")
	sshPort := flag.Int("ssh-port", 22, "tailnet port for the SSH shell")
	dropAddr := flag.String("drop-addr", "127.0.0.1:3999", "loopback address that closes SSH sessions")
	flag.Parse()

	srv := &tsnet.Server{
		Hostname:   *hostname,
		ControlURL: *control,
		AuthKey:    *key,
		Dir:        os.TempDir() + "/motion-peer-" + *hostname,
		Logf:       func(format string, args ...any) {},
	}
	defer srv.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	status, err := srv.Up(ctx)
	if err != nil {
		log.Fatalf("join the tailnet: %v", err)
	}
	mux := http.NewServeMux()
	// Loopback only: the recording runner drops SSH sessions to exercise
	// Reconnect without touching the tailnet.
	go func() {
		mux := http.NewServeMux()
		mux.HandleFunc("/drop", func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprintf(w, "dropped %d\n", dropConns())
		})
		log.Printf("control on 127.0.0.1%s", *dropAddr)
		log.Print(http.ListenAndServe(*dropAddr, mux))
	}()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		fmt.Fprint(w, page)
	})
	ln, err := srv.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("listen on %d: %v", *port, err)
	}
	if c, ok := ln.(net.Listener); ok {
		log.Printf("serving on %v (net %s)", c.Addr(), status.TailscaleIPs)
	}
	if addr, err := serveSSH(srv, fmt.Sprintf(":%d", *sshPort)); err != nil {
		log.Printf("ssh on %d: %v", *sshPort, err)
	} else {
		log.Printf("ssh shell on %s", addr)
	}
	log.Fatal(http.Serve(ln, mux))
}
