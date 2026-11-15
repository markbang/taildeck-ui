package main

// A tiny SSH server on the tailnet, so the recording has a real shell to
// drive: vim, htop and a prompt that is not canned bytes. Any public key and
// any password are accepted; every session gets /bin/bash on a pty.

import (
	"crypto/rand"
	"crypto/rsa"
	"encoding/binary"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"sync"

	"github.com/creack/pty"
	"golang.org/x/crypto/ssh"
	"tailscale.com/tsnet"
)

func serveSSH(srv *tsnet.Server, addr string) (string, error) {
	ln, err := srv.Listen("tcp", addr)
	if err != nil {
		return "", err
	}
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return "", err
	}
	signer, err := ssh.NewSignerFromKey(key)
	if err != nil {
		return "", err
	}
	config := &ssh.ServerConfig{
		PublicKeyCallback: func(ssh.ConnMetadata, ssh.PublicKey) (*ssh.Permissions, error) {
			return nil, nil
		},
		PasswordCallback: func(ssh.ConnMetadata, []byte) (*ssh.Permissions, error) {
			return nil, nil
		},
	}
	config.AddHostKey(signer)
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go handleConn(conn, config)
		}
	}()
	home, _ := os.UserHomeDir()
	return fmt.Sprintf("%v (home %s)", ln.Addr(), home), nil
}

func handleConn(conn net.Conn, config *ssh.ServerConfig) {
	defer conn.Close()
	sc, chans, reqs, err := ssh.NewServerConn(conn, config)
	if err != nil {
		return
	}
	defer sc.Close()
	active.mu.Lock()
	active.conns = append(active.conns, sc)
	active.mu.Unlock()
	defer func() {
		active.mu.Lock()
		for i, c := range active.conns {
			if c == sc {
				active.conns = append(active.conns[:i], active.conns[i+1:]...)
				break
			}
		}
		active.mu.Unlock()
	}()
	go ssh.DiscardRequests(reqs)
	for newChannel := range chans {
		if newChannel.ChannelType() != "session" {
			newChannel.Reject(ssh.UnknownChannelType, "only sessions")
			continue
		}
		channel, requests, err := newChannel.Accept()
		if err != nil {
			return
		}
		go handleSession(channel, requests)
	}
}

func handleSession(channel ssh.Channel, requests <-chan *ssh.Request) {
	defer channel.Close()
	var (
		cmd  *exec.Cmd
		f    *os.File
		once sync.Once
		mu   sync.Mutex
		size = pty.Winsize{Rows: 24, Cols: 80}
	)
	start := func() {
		once.Do(func() {
			cmd = exec.Command("/bin/bash", "-l")
			cmd.Env = append(os.Environ(),
				"TERM=xterm-256color",
				"HOME="+homeDir(),
				"PS1=\\u@\\h:\\w\\$ ",
			)
			mu.Lock()
			f, _ = pty.StartWithSize(cmd, &size)
			mu.Unlock()
			if f == nil {
				channel.Close()
				return
			}
			go func() { io.Copy(channel, f) }()
			go func() { io.Copy(f, channel) }()
			go func() {
				_ = cmd.Wait()
				channel.Close()
			}()
		})
	}
	for req := range requests {
		switch req.Type {
		case "pty-req":
			var reqSize struct{ Rows, Cols uint32 }
			// The payload starts with TERM (string) then four uint32s.
			if len(req.Payload) > 4 {
				termLen := int(binary.BigEndian.Uint32(req.Payload[:4]))
				rest := req.Payload[4+termLen:]
				if len(rest) >= 16 {
					reqSize.Cols = binary.BigEndian.Uint32(rest[0:4])
					reqSize.Rows = binary.BigEndian.Uint32(rest[4:8])
				}
			}
			if reqSize.Rows > 0 && reqSize.Cols > 0 {
				mu.Lock()
				size = pty.Winsize{Rows: uint16(reqSize.Rows), Cols: uint16(reqSize.Cols)}
				mu.Unlock()
			}
			req.Reply(true, nil)
			start()
		case "shell":
			req.Reply(true, nil)
			start()
		case "window-change":
			if len(req.Payload) >= 8 {
				rows := binary.BigEndian.Uint32(req.Payload[4:8])
				cols := binary.BigEndian.Uint32(req.Payload[0:4])
				mu.Lock()
				size = pty.Winsize{Rows: uint16(rows), Cols: uint16(cols)}
				if f != nil {
					_ = pty.Setsize(f, &size)
				}
				mu.Unlock()
			}
			req.Reply(true, nil)
		default:
			req.Reply(false, nil)
		}
	}
	mu.Lock()
	if f != nil {
		f.Close()
	}
	if cmd != nil && cmd.Process != nil {
		_ = cmd.Process.Kill()
	}
	mu.Unlock()
}

func homeDir() string {
	if home, err := os.UserHomeDir(); err == nil {
		return home
	}
	return "/root"
}

var active = struct {
	mu    sync.Mutex
	conns []*ssh.ServerConn
}{}

// dropConns closes every SSH connection, so the app's session sees a drop and
// the recording can press Reconnect. Returns how many it closed.
func dropConns() int {
	active.mu.Lock()
	conns := active.conns
	active.conns = nil
	active.mu.Unlock()
	for _, c := range conns {
		_ = c.Close()
	}
	return len(conns)
}

var _ = log.Printf
