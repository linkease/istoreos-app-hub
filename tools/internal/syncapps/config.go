package syncapps

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

type Config struct {
	Version    int                   `yaml:"version"`
	LegacyRoot string                `yaml:"legacy_root"`
	AppsRoot   string                `yaml:"apps_root"`
	Rsync      RsyncConfig           `yaml:"rsync"`
	Apps       map[string]AppMapping `yaml:"apps"`

	// Computed
	repoRootAbs  string
	legacyRootAbs string
}

type RsyncConfig struct {
	Bin          string   `yaml:"bin"`
	Excludes     []string `yaml:"excludes"`
	ExcludeFiles []string `yaml:"exclude_files"`
}

type AppMapping struct {
	Services []Pair `yaml:"services"`
	Luci     []Pair `yaml:"luci"`
	Meta     []Pair `yaml:"meta"`
}

type Pair struct {
	Local  string `yaml:"local"`
	Remote string `yaml:"remote"`
}

func LoadConfig(path string) (*Config, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var cfg Config
	if err := yaml.Unmarshal(b, &cfg); err != nil {
		return nil, err
	}

	if cfg.Version != 1 {
		return nil, fmt.Errorf("unsupported version: %d", cfg.Version)
	}

	configAbs, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	cfg.repoRootAbs = filepath.Dir(configAbs)

	if strings.TrimSpace(cfg.AppsRoot) == "" {
		cfg.AppsRoot = "apps"
	}

	// legacy_root precedence:
	// 1) syncapps.yaml legacy_root (if non-empty)
	// 2) env LEGACY_ROOT (if set)
	// 3) error
	if strings.TrimSpace(cfg.LegacyRoot) == "" {
		cfg.LegacyRoot = os.Getenv("LEGACY_ROOT")
	}
	if strings.TrimSpace(cfg.LegacyRoot) == "" {
		return nil, fmt.Errorf("legacy_root is required (set syncapps.yaml:legacy_root or env LEGACY_ROOT)")
	}

	if filepath.IsAbs(cfg.LegacyRoot) {
		cfg.legacyRootAbs = filepath.Clean(cfg.LegacyRoot)
	} else {
		cfg.legacyRootAbs = filepath.Clean(filepath.Join(cfg.repoRootAbs, cfg.LegacyRoot))
	}

	if strings.TrimSpace(cfg.Rsync.Bin) == "" {
		cfg.Rsync.Bin = "rsync"
	}

	if cfg.Apps == nil {
		cfg.Apps = map[string]AppMapping{}
	}

	return &cfg, nil
}

func SaveConfig(path string, cfg *Config) error {
	b, err := yaml.Marshal(cfg)
	if err != nil {
		return err
	}
	// yaml.v3 does not guarantee a trailing newline.
	if len(b) == 0 || b[len(b)-1] != '\n' {
		b = append(b, '\n')
	}
	return os.WriteFile(path, b, 0o664)
}

func ListApps(cfg *Config) []string {
	var names []string
	for name := range cfg.Apps {
		names = append(names, name)
	}
	sort.Strings(names)

	var out []string
	for _, name := range names {
		m := cfg.Apps[name]
		var slots []string
		if len(m.Services) > 0 {
			slots = append(slots, "services")
		}
		if len(m.Luci) > 0 {
			slots = append(slots, "luci")
		}
		if len(m.Meta) > 0 {
			slots = append(slots, "meta")
		}
		out = append(out, fmt.Sprintf("%s\t(%s)", name, strings.Join(slots, ",")))
	}
	return out
}

func (cfg *Config) resolveLocal(p string) (string, error) {
	if strings.TrimSpace(p) == "" {
		return "", fmt.Errorf("local path is required")
	}
	if filepath.IsAbs(p) {
		return filepath.Clean(p), nil
	}
	return filepath.Clean(filepath.Join(cfg.repoRootAbs, p)), nil
}

func (cfg *Config) resolveRemote(p string) (string, error) {
	if strings.TrimSpace(p) == "" {
		return "", fmt.Errorf("remote path is required")
	}
	if filepath.IsAbs(p) {
		return filepath.Clean(p), nil
	}
	return filepath.Clean(filepath.Join(cfg.legacyRootAbs, p)), nil
}
