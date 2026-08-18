//go:build !darwin && !linux

package agentsession

import "os"

func fileOwnedByCurrentUser(os.FileInfo) bool {
	return false
}

func fileInode(os.FileInfo) uint64 {
	return 0
}
