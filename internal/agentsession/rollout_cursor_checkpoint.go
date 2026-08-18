package agentsession

import (
	"bytes"
	"crypto/sha256"
	"io"
	"os"
)

func rolloutSeedHash(path string) ([sha256.Size]byte, int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return [sha256.Size]byte{}, 0, err
	}
	defer func() { _ = file.Close() }()
	data := make([]byte, rolloutChunkBytes)
	count, err := file.Read(data)
	if err != nil && err != io.EOF {
		return [sha256.Size]byte{}, int64(count), err
	}
	seed := data[:count]
	if newline := bytes.IndexByte(seed, '\n'); newline >= 0 {
		seed = seed[:newline+1]
	}
	return sha256.Sum256(seed), int64(count), nil
}

func (c *RolloutCursor) checkpointMatches() (bool, int64, error) {
	file, err := os.Open(c.path)
	if err != nil {
		return false, 0, err
	}
	defer func() { _ = file.Close() }()
	if _, err := file.Seek(c.checkpointStart, io.SeekStart); err != nil {
		return false, 0, err
	}
	data := make([]byte, c.checkpointSize)
	count, err := io.ReadFull(file, data)
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return false, int64(count), err
	}
	return count == c.checkpointSize && sha256.Sum256(data[:count]) == c.checkpointHash, int64(count), nil
}

func (c *RolloutCursor) captureCheckpoint() (int64, error) {
	if c.offset == 0 {
		c.hasCheckpoint = false
		return 0, nil
	}
	const window = int64(4 * 1024)
	start := c.offset - window
	if start < 0 {
		start = 0
	}
	file, err := os.Open(c.path)
	if err != nil {
		return 0, err
	}
	defer func() { _ = file.Close() }()
	if _, err := file.Seek(start, io.SeekStart); err != nil {
		return 0, err
	}
	data := make([]byte, c.offset-start)
	count, err := io.ReadFull(file, data)
	if err != nil && err != io.EOF && err != io.ErrUnexpectedEOF {
		return int64(count), err
	}
	c.checkpointStart = start
	c.checkpointSize = count
	c.checkpointHash = sha256.Sum256(data[:count])
	c.hasCheckpoint = count > 0
	return int64(count), nil
}
