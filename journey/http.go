package main

import (
	"log"
	"net"
	"net/http"
	_ "net/http/pprof"
)

// serve http endpoint and return its host:port or an error
func serve() (string, error) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return "", err
	}
	go func() {
		log.Println(http.Serve(l, http.DefaultServeMux))
	}()

	return l.Addr().String(), nil
}
