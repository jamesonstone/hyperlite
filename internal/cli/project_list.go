package cli

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jamesonstone/hyperlite/internal/command"
	"github.com/jamesonstone/hyperlite/internal/config"
	"github.com/jamesonstone/hyperlite/internal/discovery"
	"github.com/spf13/cobra"
)

type listedProject struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Path       string `json:"path"`
	Repository string `json:"repository,omitempty"`
	Base       string `json:"base"`
}

type projectList struct {
	Projects []listedProject `json:"projects"`
}

func (a App) configuredProjectListCommand(configPath *string) *cobra.Command {
	var jsonOutput bool
	command := &cobra.Command{
		Use:   "list",
		Short: "List configured Hyperlite repositories",
		Args:  noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			return a.runConfiguredProjectList(cmd.Context(), *configPath, jsonOutput)
		},
	}
	command.Flags().BoolVar(&jsonOutput, "json", false, "emit JSON only")
	return command
}

func (a App) runConfiguredProjectList(ctx context.Context, configPath string, jsonOutput bool) error {
	repos, err := a.discoverConfiguredRepositories(ctx, configPath)
	if err != nil {
		return err
	}
	list := projectList{Projects: make([]listedProject, 0, len(repos))}
	for _, repo := range repos {
		list.Projects = append(list.Projects, listedProject{
			ID:         "project:" + repo.Path,
			Name:       repo.Name,
			Path:       repo.Path,
			Repository: repo.GitHub,
			Base:       repo.Base,
		})
	}
	if jsonOutput {
		return json.NewEncoder(a.Out).Encode(list)
	}
	for _, project := range list.Projects {
		if _, err := fmt.Fprintf(a.Out, "%s\t%s\n", project.Name, project.Path); err != nil {
			return err
		}
	}
	return nil
}

func (a App) discoverConfiguredRepositories(ctx context.Context, configPath string) ([]config.Repository, error) {
	path, err := config.EnsureDefaultConfig(configPath)
	if err != nil {
		return nil, err
	}
	cfg, err := config.Load(path)
	if err != nil {
		return nil, err
	}
	discoverer := discovery.Discoverer{Runner: a.commandRunner()}
	return discoverer.Discover(ctx, cfg.Projects).Repositories, nil
}

func (a App) commandRunner() command.Runner {
	if a.Runner != nil {
		return a.Runner
	}
	return command.ExecRunner{}
}
