package main

import (
	"fmt"
	"os"

	"github.com/jamesonstone/hyperlite/internal/cli"
)

func main() {
	if err := cli.New().Execute(); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(cli.ExitCode(err))
	}
}
