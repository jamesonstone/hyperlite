package config

func Example() string {
	return `version: 2

settings:
  scan_interval: 1m
  remote_refresh_interval: 45m
  stale_after: 24h
  max_parallel: 4
  github_author: "@me"
  github_scope: mine

projects: []

sources:
  - path: ~/go/src/github.com

repositories:
  - name: hyperlite
    path: ~/go/src/github.com/jamesonstone/hyperlite
    github: jamesonstone/hyperlite
    base: main
    remote: origin
`
}
