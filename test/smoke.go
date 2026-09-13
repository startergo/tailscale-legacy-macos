package main

import (
	"fmt"
	"net"
	"sync"
	"time"
)

func main() {
	var wg sync.WaitGroup
	ch := make(chan int, 4)
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(n int) { defer wg.Done(); time.Sleep(50 * time.Millisecond); ch <- n }(i)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fmt.Println("listen error:", err)
		return
	}
	defer ln.Close()
	wg.Wait()
	fmt.Println("ok goroutines + net on", ln.Addr())
}
