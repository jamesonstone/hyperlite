package agentsession

import (
	"bytes"
	"crypto/sha256"
	"errors"
	"io"
	"os"
	"reflect"
	"time"
)

const (
	rolloutChunkBytes = 64 * 1024
	rolloutTurnBytes  = 512 * 1024
	rolloutTurnRows   = 128
	maxRolloutRecord  = 1024 * 1024
	maxDiscoveryBytes = 32 * 1024 * 1024
)

var ErrRolloutIdentityMismatch = errors.New("rollout identity does not match its exact seed")

type RolloutCursor struct {
	path            string
	seed            Event
	identity        os.FileInfo
	offset          int64
	partial         []byte
	discarding      bool
	projection      Event
	messages        []Message
	running         map[string]string
	seedHash        [sha256.Size]byte
	hasSeedHash     bool
	checkpointStart int64
	checkpointSize  int
	checkpointHash  [sha256.Size]byte
	hasCheckpoint   bool
}

func NewRolloutCursor(path string, seed Event) *RolloutCursor {
	return &RolloutCursor{path: path, seed: seed, running: make(map[string]string)}
}

func (c *RolloutCursor) BindSeed(seed Event) {
	c.seed = mergeRolloutSeed(c.seed, seed)
}

func (c *RolloutCursor) Advance(now time.Time, byteBudget int64, rowBudget int) (Event, bool, bool, int64, error) {
	if byteBudget <= 0 || byteBudget > rolloutTurnBytes {
		byteBudget = rolloutTurnBytes
	}
	if rowBudget <= 0 || rowBudget > rolloutTurnRows {
		rowBudget = rolloutTurnRows
	}
	info, err := os.Stat(c.path)
	if err != nil || !info.Mode().IsRegular() {
		return Event{}, false, false, 0, errors.New("rollout is unavailable")
	}
	seedHash, signatureBytes, err := rolloutSeedHash(c.path)
	if err != nil {
		return Event{}, false, false, 0, err
	}
	setupBytes := signatureBytes
	seedChanged := c.hasSeedHash && c.seedHash != seedHash
	needsReset := c.identity == nil || !os.SameFile(c.identity, info) || info.Size() < c.offset || seedChanged
	if !needsReset && c.hasCheckpoint {
		matches, checkedBytes, checkErr := c.checkpointMatches()
		setupBytes += checkedBytes
		if checkErr != nil {
			return Event{}, false, false, setupBytes, checkErr
		}
		needsReset = !matches
	}
	if needsReset {
		resetBytes, resetErr := c.reset(info, now)
		err = resetErr
		setupBytes += resetBytes
		if err != nil {
			return Event{}, false, false, 0, err
		}
		c.seedHash = seedHash
		c.hasSeedHash = true
	}
	before := cloneRolloutEvent(c.projection)
	file, err := os.Open(c.path)
	if err != nil {
		return Event{}, false, false, 0, err
	}
	defer func() { _ = file.Close() }()
	if _, err := file.Seek(c.offset, io.SeekStart); err != nil {
		return Event{}, false, false, 0, err
	}
	buffer := make([]byte, rolloutChunkBytes)
	readBytes := setupBytes
	rows := 0
	readTarget := byteBudget - 4*1024
	if readTarget < setupBytes {
		readTarget = setupBytes
	}
	for readBytes < readTarget && rows < rowBudget {
		limit := int64(len(buffer))
		if remaining := readTarget - readBytes; remaining < limit {
			limit = remaining
		}
		count, readErr := file.Read(buffer[:limit])
		if count > 0 {
			consumed, parsedRows := c.consume(buffer[:count], now, rowBudget-rows)
			c.offset += int64(consumed)
			readBytes += int64(consumed)
			rows += parsedRows
		}
		if readErr == io.EOF {
			break
		}
		if readErr != nil {
			return Event{}, false, false, readBytes, readErr
		}
		if count == 0 {
			break
		}
	}
	checkpointBytes, checkpointErr := c.captureCheckpoint()
	readBytes += checkpointBytes
	if checkpointErr != nil {
		return Event{}, false, false, readBytes, checkpointErr
	}
	if c.projection.SessionID == "" {
		return Event{}, false, c.offset < info.Size(), readBytes, nil
	}
	if c.seed.SessionID != "" && c.projection.SessionID != c.seed.SessionID {
		return Event{}, false, false, readBytes, ErrRolloutIdentityMismatch
	}
	c.finalizeProjection(now)
	changed := !reflect.DeepEqual(before, c.projection)
	return cloneRolloutEvent(c.projection), changed, c.offset < info.Size(), readBytes, nil
}

func (c *RolloutCursor) reset(info os.FileInfo, now time.Time) (int64, error) {
	c.identity = info
	c.offset = 0
	c.partial = nil
	c.discarding = false
	c.hasCheckpoint = false
	c.messages = nil
	clear(c.running)
	c.projection = Event{
		Schema: EventSchema, Provider: "codex", Profile: "codex",
		SessionID: c.seed.SessionID, Event: "rollout", Phase: PhaseIdle,
		Source: SourceRollout, OccurredAt: now,
		Routing: Routing{BundleID: "com.openai.codex"}, RolloutPath: c.path,
	}
	if info.Size() <= maxRolloutTail {
		return 0, nil
	}
	file, err := os.Open(c.path)
	if err != nil {
		return 0, err
	}
	defer func() { _ = file.Close() }()
	prefix := make([]byte, rolloutChunkBytes)
	count, err := file.Read(prefix)
	if err != nil && err != io.EOF {
		return int64(count), err
	}
	if newline := bytes.IndexByte(prefix[:count], '\n'); newline >= 0 {
		c.consumeLine(prefix[:newline], now)
	}
	start := info.Size() - maxRolloutTail
	if _, err := file.Seek(start, io.SeekStart); err != nil {
		return int64(count), err
	}
	probe := make([]byte, rolloutChunkBytes)
	probeCount, err := file.Read(probe)
	if err != nil && err != io.EOF {
		return int64(count + probeCount), err
	}
	newline := bytes.IndexByte(probe[:probeCount], '\n')
	if newline < 0 {
		c.offset = start + int64(probeCount)
		c.discarding = true
		return int64(count + probeCount), nil
	}
	c.offset = start + int64(newline+1)
	c.partial = nil
	return int64(count + probeCount), nil
}
