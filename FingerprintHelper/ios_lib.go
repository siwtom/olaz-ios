//go:build ios

package main

import "C"
import (
	"log"
	"net"
	"sync"
)

var (
	iosMu       sync.Mutex
	iosListener net.Listener
	iosPort     int
)

//export OlazFPStartLoopback
func OlazFPStartLoopback() C.int {
	iosMu.Lock()
	defer iosMu.Unlock()

	if iosListener != nil && iosPort > 0 {
		return C.int(iosPort)
	}

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Printf("fingerprint-helper ios listen failed: %v", err)
		return -1
	}

	addr, ok := ln.Addr().(*net.TCPAddr)
	if !ok || addr.Port <= 0 {
		_ = ln.Close()
		log.Printf("fingerprint-helper ios invalid addr: %T", ln.Addr())
		return -1
	}

	iosListener = ln
	iosPort = addr.Port
	log.Printf("fingerprint-helper v%d (%s) loopback listening on 127.0.0.1:%d", helperVersion, profileName, iosPort)

	go func(listener net.Listener) {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go handleConn(conn)
		}
	}(ln)

	return C.int(iosPort)
}

//export OlazFPStop
func OlazFPStop() {
	iosMu.Lock()
	ln := iosListener
	iosListener = nil
	iosPort = 0
	iosMu.Unlock()

	if ln != nil {
		_ = ln.Close()
	}
}

func main() {}
