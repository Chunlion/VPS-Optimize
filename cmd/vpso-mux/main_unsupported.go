//go:build !linux

package main

import "log"

func main() {
	log.Fatal("vpso-mux supports Linux only")
}
