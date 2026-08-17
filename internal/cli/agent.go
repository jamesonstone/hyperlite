package cli

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"strconv"
	"time"

	"github.com/jamesonstone/hyperlite/internal/agentsession"
	"github.com/spf13/cobra"
)

func (a App) agentCommand() *cobra.Command {
	command := &cobra.Command{Use: "agent", Short: "Manage local coding-agent sessions", Args: noArgs}
	command.AddCommand(a.agentSessionsCommand(), a.agentHookCommand(), a.agentIntegrationsCommand())
	return command
}

func (a App) agentSessionsCommand() *cobra.Command {
	command := &cobra.Command{Use: "sessions", Short: "Run the local agent-session service", Args: noArgs}
	command.AddCommand(a.agentSessionsServeCommand())
	return command
}

func (a App) agentSessionsServeCommand() *cobra.Command {
	var socketPath string
	var disableCodex bool
	command := &cobra.Command{
		Use: "serve", Short: "Serve versioned local agent-session snapshots", Args: noArgs,
		RunE: func(cmd *cobra.Command, _ []string) error {
			home, err := os.UserHomeDir()
			if err != nil {
				return fmt.Errorf("resolve home directory: %w", err)
			}
			executable, err := os.Executable()
			if err != nil {
				return fmt.Errorf("resolve bridge executable: %w", err)
			}
			return agentsession.RunService(cmd.Context(), a.input(), a.Out, a.Err, agentsession.ServiceOptions{
				SocketPath: socketPath, Home: home, BridgePath: executable, DisableCodex: disableCodex,
			})
		},
	}
	command.Flags().StringVar(&socketPath, "socket", "", "override the private agent socket path")
	command.Flags().BoolVar(&disableCodex, "no-codex", false, "disable Codex discovery for isolated testing")
	_ = command.Flags().MarkHidden("no-codex")
	return command
}

func (a App) agentHookCommand() *cobra.Command {
	var profileID, socketPath string
	var waitSeconds int
	command := &cobra.Command{
		Use: "hook", Short: "Forward one provider hook to the local session service", Args: noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			profile, ok := agentsession.ProfileByID(profileID)
			if !ok {
				return usageError{fmt.Errorf("unknown agent profile %q", profileID)}
			}
			raw, err := io.ReadAll(io.LimitReader(a.input(), 1024*1024+1))
			if err != nil || len(raw) > 1024*1024 {
				return errors.New("hook payload exceeds the safety limit")
			}
			event, err := agentsession.NormalizeHook(profile, raw, hookEnvironment(), time.Now().UTC())
			if err != nil {
				return err
			}
			if socketPath == "" {
				socketPath = agentsession.RuntimeSocketPath(hookEnvironment())
			}
			return agentsession.SendHook(event, socketPath, time.Duration(waitSeconds)*time.Second, a.Out)
		},
	}
	command.Flags().StringVar(&profileID, "profile", "", "provider profile identifier")
	command.Flags().StringVar(&socketPath, "socket", "", "override the private agent socket path")
	command.Flags().IntVar(&waitSeconds, "wait-seconds", 86400, "maximum response wait")
	_ = command.MarkFlagRequired("profile")
	return command
}

func (a App) agentIntegrationsCommand() *cobra.Command {
	command := &cobra.Command{Use: "integrations", Short: "Inspect or reconcile agent integrations", Args: noArgs}
	command.AddCommand(a.agentIntegrationsListCommand(), a.agentIntegrationMutationCommand(true), a.agentIntegrationMutationCommand(false))
	return command
}

func (a App) agentIntegrationsListCommand() *cobra.Command {
	return &cobra.Command{
		Use: "list", Short: "List supported local integrations", Args: noArgs,
		RunE: func(_ *cobra.Command, _ []string) error {
			home, err := os.UserHomeDir()
			if err != nil {
				return err
			}
			executable, _ := os.Executable()
			return json.NewEncoder(a.Out).Encode(agentsession.DetectIntegrations(home, executable))
		},
	}
}

func (a App) agentIntegrationMutationCommand(enable bool) *cobra.Command {
	name := "disable"
	if enable {
		name = "enable"
	}
	return &cobra.Command{
		Use: name + " <profile>", Short: name + " one Hyperlite-owned integration", Args: cobra.ExactArgs(1),
		RunE: func(_ *cobra.Command, args []string) error {
			home, err := os.UserHomeDir()
			if err != nil {
				return err
			}
			executable, err := os.Executable()
			if err != nil {
				return err
			}
			status, err := agentsession.ReconcileIntegration(home, executable, args[0], enable)
			if err != nil {
				return err
			}
			if !enable {
				routingPath, pathErr := agentsession.RoutingPath(hookEnvironment(), home)
				if pathErr != nil {
					return pathErr
				}
				if err := agentsession.RemoveRoutingProfile(routingPath, args[0], time.Now().UTC()); err != nil {
					return err
				}
			}
			return json.NewEncoder(a.Out).Encode(status)
		},
	}
}

func hookEnvironment() map[string]string {
	keys := []string{"PWD", "TERM_PROGRAM", "TERM_SESSION_ID", "ITERM_SESSION_ID", "TMUX", "TMUX_PANE", "__CFBundleIdentifier", "TMPDIR", "XDG_STATE_HOME"}
	result := make(map[string]string, len(keys))
	for _, key := range keys {
		if value := os.Getenv(key); value != "" {
			result[key] = value
		}
	}
	result["UID"] = strconv.Itoa(os.Getuid())
	return result
}
