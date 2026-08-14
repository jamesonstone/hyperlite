package pinboard

import (
	"bytes"
	"errors"
	"fmt"
	"io"
	"strings"
	"time"

	"go.yaml.in/yaml/v3"
)

const frontMatterDelimiter = "---\n"

type noteMetadata struct {
	ID                       string    `yaml:"id"`
	Title                    string    `yaml:"title"`
	CreatedAt                yamlTime  `yaml:"created_at"`
	UpdatedAt                yamlTime  `yaml:"updated_at"`
	ForkedFrom               string    `yaml:"forked_from,omitempty"`
	ArchivedAt               *yamlTime `yaml:"archived_at,omitempty"`
	ArchivedFromSectionID    string    `yaml:"archived_from_section_id,omitempty"`
	ArchivedFromSectionTitle string    `yaml:"archived_from_section_title,omitempty"`
}

type yamlTime struct{ value string }

func (t yamlTime) MarshalYAML() (any, error)            { return t.value, nil }
func (t *yamlTime) UnmarshalYAML(node *yaml.Node) error { t.value = node.Value; return nil }

func encodeNote(note Note, archived bool) ([]byte, error) {
	if err := validateNote(note, archived); err != nil {
		return nil, err
	}
	metadata := noteMetadata{
		ID: note.ID, Title: note.Title,
		CreatedAt:                yamlTime{note.CreatedAt.UTC().Format(timeFormat)},
		UpdatedAt:                yamlTime{note.UpdatedAt.UTC().Format(timeFormat)},
		ForkedFrom:               note.ForkedFrom,
		ArchivedFromSectionID:    note.ArchivedFromSectionID,
		ArchivedFromSectionTitle: note.ArchivedFromSectionTitle,
	}
	if note.ArchivedAt != nil {
		value := yamlTime{note.ArchivedAt.UTC().Format(timeFormat)}
		metadata.ArchivedAt = &value
	}
	encoded, err := yaml.Marshal(metadata)
	if err != nil {
		return nil, fmt.Errorf("encode note metadata: %w", err)
	}
	return []byte(frontMatterDelimiter + string(encoded) + frontMatterDelimiter + note.Description), nil
}

func decodeNote(contents []byte, archived bool) (Note, error) {
	if !bytes.HasPrefix(contents, []byte(frontMatterDelimiter)) {
		return Note{}, errors.New("note is missing YAML front matter")
	}
	remainder := contents[len(frontMatterDelimiter):]
	closing := bytes.Index(remainder, []byte("\n"+frontMatterDelimiter))
	if closing < 0 {
		return Note{}, errors.New("note front matter is not closed")
	}
	decoder := yaml.NewDecoder(bytes.NewReader(remainder[:closing]))
	decoder.KnownFields(true)
	var metadata noteMetadata
	if err := decoder.Decode(&metadata); err != nil {
		return Note{}, fmt.Errorf("decode note metadata: %w", err)
	}
	var extra any
	if err := decoder.Decode(&extra); !errors.Is(err, io.EOF) {
		if err == nil {
			return Note{}, errors.New("note metadata contains multiple YAML documents")
		}
		return Note{}, fmt.Errorf("decode note metadata: %w", err)
	}
	createdAt, err := parseTime(metadata.CreatedAt.value)
	if err != nil {
		return Note{}, fmt.Errorf("decode created_at: %w", err)
	}
	updatedAt, err := parseTime(metadata.UpdatedAt.value)
	if err != nil {
		return Note{}, fmt.Errorf("decode updated_at: %w", err)
	}
	note := Note{
		ID: metadata.ID, Title: metadata.Title,
		Description: string(remainder[closing+len("\n"+frontMatterDelimiter):]),
		CreatedAt:   createdAt, UpdatedAt: updatedAt, ForkedFrom: metadata.ForkedFrom,
		ArchivedFromSectionID:    metadata.ArchivedFromSectionID,
		ArchivedFromSectionTitle: metadata.ArchivedFromSectionTitle,
	}
	if metadata.ArchivedAt != nil {
		value, parseErr := parseTime(metadata.ArchivedAt.value)
		if parseErr != nil {
			return Note{}, fmt.Errorf("decode archived_at: %w", parseErr)
		}
		note.ArchivedAt = &value
	}
	if err := validateNote(note, archived); err != nil {
		return Note{}, err
	}
	return note, nil
}

func parseTime(value string) (time.Time, error) {
	if strings.TrimSpace(value) == "" {
		return time.Time{}, errors.New("timestamp is required")
	}
	parsed, err := time.Parse(timeFormat, value)
	if err != nil {
		return time.Time{}, err
	}
	return parsed.UTC(), nil
}
