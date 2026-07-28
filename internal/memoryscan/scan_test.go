package memoryscan

import (
	"os"
	"path/filepath"
	"testing"
)

func TestScanReadsActiveSpecIntentAndExactDeliveryIssue(t *testing.T) {
	root := t.TempDir()
	specDirectory := filepath.Join(root, "docs", "specs", "0003-event-platform")
	if err := os.MkdirAll(specDirectory, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(root, "docs"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "docs", "CONSTITUTION.md"), []byte("# Contract\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	spec := `---
phase: delivery
feature:
  id: "0003"
  slug: event-platform
references:
  - id: constitution
    type: repo_doc
    target: docs/CONSTITUTION.md
    relation: constrains
---
# Enterprise event platform

## Summary

Add a durable event platform.

## Authority

R2 retains policy authority while Event Sink owns immutable history.

## Implementation Plan

1. Provision the production infrastructure and
   deploy the worker services.

## Delivery Decision

Platform uses issue ` + "`#22`" + `. Implementation is owned by GitHub issue ` + "`#26`" + `
and branch ` + "`GH-26`" + `.
`
	if err := os.WriteFile(filepath.Join(specDirectory, "SPEC.md"), []byte(spec), 0o644); err != nil {
		t.Fatal(err)
	}
	result := Scan(root)
	if len(result.Diagnostics) != 0 || len(result.Documents) != 1 {
		t.Fatalf("result = %#v", result)
	}
	document := result.Documents[0]
	if !document.Selected || document.Phase != "delivery" ||
		len(document.IssueNumbers) != 1 || document.IssueNumbers[0] != 26 {
		t.Fatalf("document identity = %#v", document)
	}
	if document.Purpose != "Add a durable event platform." {
		t.Fatalf("purpose = %q", document.Purpose)
	}
	if len(document.Obligations) != 1 ||
		document.Obligations[0].Summary != "Provision the production infrastructure and deploy the worker services." {
		t.Fatalf("obligations = %#v", document.Obligations)
	}
	referenced := document.ReadReferencedDocuments(root)
	if len(referenced) != 1 || referenced[0].Path != "docs/CONSTITUTION.md" {
		t.Fatalf("referenced documents = %#v", referenced)
	}
}

func TestCandidatesIgnoreHeadingsAndNegativeStatements(t *testing.T) {
	values := candidates(`
### Infrastructure rollout

1. No schema migration is required.
2. Deploy the production worker.
`, obligationWord, "operational")
	if len(values) != 1 || values[0].Summary != "Deploy the production worker." {
		t.Fatalf("candidates = %#v", values)
	}
}

func TestCandidatesHandleCompletedItemsAndIgnoreFencedExamples(t *testing.T) {
	values := candidates(`
- [X] Deploy the production worker.

`+"```sh"+`
deploy --production example
`+"```"+`

- Provision the infrastructure.
`, obligationWord, "operational")
	if len(values) != 2 ||
		values[0].Summary != "Deploy the production worker." || !values[0].Satisfied ||
		values[1].Summary != "Provision the infrastructure." || values[1].Satisfied {
		t.Fatalf("candidates = %#v", values)
	}
}

func TestReflectionCompletionFollowsWorkflowVersion(t *testing.T) {
	root := t.TempDir()
	for _, test := range []struct {
		id              string
		workflowVersion string
		satisfied       bool
	}{
		{id: "0001", satisfied: true},
		{id: "0002", workflowVersion: "workflow_version: 2\n", satisfied: false},
	} {
		directory := filepath.Join(root, "docs", "specs", test.id+"-feature")
		if err := os.MkdirAll(directory, 0o755); err != nil {
			t.Fatal(err)
		}
		spec := "---\n" + test.workflowVersion +
			"phase: reflect\nfeature:\n  id: \"" + test.id + "\"\n  slug: feature\n---\n" +
			"# Feature\n\n## Requirements\n\n- Deploy the production worker.\n"
		path := filepath.Join(directory, "SPEC.md")
		if err := os.WriteFile(path, []byte(spec), 0o644); err != nil {
			t.Fatal(err)
		}
		document, diagnostics := loadDocument(root, path, nil)
		if len(diagnostics) != 0 || len(document.Obligations) != 1 {
			t.Fatalf("document=%#v diagnostics=%#v", document, diagnostics)
		}
		if document.Obligations[0].Satisfied != test.satisfied {
			t.Fatalf("workflow version %d satisfied=%t, want %t",
				document.WorkflowVersion, document.Obligations[0].Satisfied, test.satisfied)
		}
	}
}
