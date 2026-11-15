package tsbridge

import (
	"net/netip"
	"testing"

	"github.com/sagernet/tailscale/ipn/ipnstate"
	"github.com/sagernet/tailscale/types/key"
	"github.com/sagernet/tailscale/types/views"
)

func TestPeerTableNames(t *testing.T) {
	st := &ipnstate.Status{Peer: map[key.NodePublic]*ipnstate.PeerStatus{
		key.NewNode().Public(): {
			HostName:     "Bangwu",
			DNSName:      "bangwu.tailnet.ts.net.",
			TailscaleIPs: []netip.Addr{netip.MustParseAddr("100.64.0.8")},
		},
		key.NewNode().Public(): {
			HostName:     "mac",
			DNSName:      "Mac.Other.ts.net.",
			TailscaleIPs: []netip.Addr{netip.MustParseAddr("100.64.0.9")},
		},
	}}
	names, _ := peerTable(st)
	for _, key := range []string{"bangwu", "bangwu.tailnet.ts.net", "mac"} {
		if _, ok := names[key]; !ok {
			t.Fatalf("%q missing from %v", key, names)
		}
	}
	if got := names["bangwu"]; got != "100.64.0.8" {
		t.Fatalf("bangwu resolved to %q", got)
	}
}

func TestPeerTableRoutesSkipExitNode(t *testing.T) {
	routes := views.SliceOf([]netip.Prefix{
		netip.MustParsePrefix("0.0.0.0/0"),
		netip.MustParsePrefix("192.168.1.0/24"),
	})
	st := &ipnstate.Status{Peer: map[key.NodePublic]*ipnstate.PeerStatus{
		key.NewNode().Public(): {
			HostName:     "router",
			TailscaleIPs: []netip.Addr{netip.MustParseAddr("100.64.0.7")},
			AllowedIPs:   &routes,
		},
	}}
	_, prefixes := peerTable(st)
	if len(prefixes) != 1 || prefixes[0].String() != "192.168.1.0/24" {
		t.Fatalf("prefixes = %v", prefixes)
	}
}

func TestNormalizeName(t *testing.T) {
	for in, want := range map[string]string{
		"Bangwu.":     "bangwu",
		"[fd7a::1]":   "fd7a::1",
		"a.b.ts.net.": "a.b.ts.net",
		"100.64.0.8":  "100.64.0.8",
	} {
		if got := normalizeName(in); got != want {
			t.Fatalf("normalizeName(%q) = %q, want %q", in, got, want)
		}
	}
}
