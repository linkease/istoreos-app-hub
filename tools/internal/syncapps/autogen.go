package syncapps

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type AutogenOptions struct {
	Force bool
}

type AutogenSummary struct {
	DiscoveredApps   int
	UpdatedApps      int
	MissingMetaApps  []string
}

func Autogen(cfg *Config, opts AutogenOptions) (*AutogenSummary, error) {
	legacy := cfg.legacyRootAbs
	if legacy == "" {
		return nil, fmt.Errorf("legacy_root not resolved")
	}

	servicesRoot := filepath.Join(legacy, "nas-packages", "network", "services")
	luciRoot := filepath.Join(legacy, "nas-packages-luci", "luci")
	actionsRoot := filepath.Join(legacy, "openwrt-app-actions", "applications")
	metaRoot := filepath.Join(legacy, "openwrt-app-meta", "applications")

	apps := map[string]bool{}

	addDirNames(servicesRoot, func(name string) (string, bool) {
		return name, true
	}, apps)
	addDirNames(luciRoot, func(name string) (string, bool) {
		if strings.HasPrefix(name, "luci-app-") {
			return strings.TrimPrefix(name, "luci-app-"), true
		}
		return "", false
	}, apps)
	addDirNames(actionsRoot, func(name string) (string, bool) {
		if strings.HasPrefix(name, "luci-app-") {
			return strings.TrimPrefix(name, "luci-app-"), true
		}
		if strings.HasPrefix(name, "app-meta-") {
			return "", false
		}
		if strings.HasPrefix(name, ".") {
			return "", false
		}
		return name, true
	}, apps)

	var names []string
	for a := range apps {
		names = append(names, a)
	}
	sort.Strings(names)

	summary := &AutogenSummary{DiscoveredApps: len(names)}

	if cfg.Apps == nil {
		cfg.Apps = map[string]AppMapping{}
	}

	for _, app := range names {
		before := cfg.Apps[app]
		after, missingMeta := buildStandardMapping(cfg, app, servicesRoot, luciRoot, actionsRoot, metaRoot)
		if missingMeta {
			summary.MissingMetaApps = append(summary.MissingMetaApps, app)
		}

		updated := false
		if opts.Force || (len(before.Services) == 0 && len(after.Services) > 0) {
			if len(after.Services) > 0 {
				before.Services = after.Services
				updated = true
			}
		}
		if opts.Force || (len(before.Luci) == 0 && len(after.Luci) > 0) {
			if len(after.Luci) > 0 {
				before.Luci = after.Luci
				updated = true
			}
		}
		if opts.Force || (len(before.Meta) == 0 && len(after.Meta) > 0) {
			if len(after.Meta) > 0 {
				before.Meta = after.Meta
				updated = true
			}
		}

		if updated {
			cfg.Apps[app] = before
			summary.UpdatedApps++
		} else {
			// Ensure the app exists in config if any mapping is present or force is used.
			if _, ok := cfg.Apps[app]; !ok && (opts.Force || len(after.Services)+len(after.Luci)+len(after.Meta) > 0) {
				cfg.Apps[app] = before
			}
		}
	}

	sort.Strings(summary.MissingMetaApps)
	return summary, nil
}

func addDirNames(root string, mapName func(string) (string, bool), dst map[string]bool) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return
	}
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		name := e.Name()
		app, ok := mapName(name)
		if !ok {
			continue
		}
		app = strings.TrimSpace(app)
		if app == "" {
			continue
		}
		dst[app] = true
	}
}

func buildStandardMapping(cfg *Config, app string, servicesRoot, luciRoot, actionsRoot, metaRoot string) (AppMapping, bool) {
	var m AppMapping

	// services: prefer nas-packages, fallback to openwrt-app-actions (non luci-app).
	if dirExists(filepath.Join(servicesRoot, app)) {
		m.Services = []Pair{{
			Local:  filepath.ToSlash(filepath.Join(cfg.AppsRoot, app, app)),
			Remote: filepath.ToSlash(filepath.Join("nas-packages", "network", "services", app)),
		}}
	} else if dirExists(filepath.Join(actionsRoot, app)) {
		m.Services = []Pair{{
			Local:  filepath.ToSlash(filepath.Join(cfg.AppsRoot, app, app)),
			Remote: filepath.ToSlash(filepath.Join("openwrt-app-actions", "applications", app)),
		}}
	}

	// luci: prefer nas-packages-luci, fallback to openwrt-app-actions.
	luciPkg := "luci-app-" + app
	if dirExists(filepath.Join(luciRoot, luciPkg)) {
		m.Luci = []Pair{{
			Local:  filepath.ToSlash(filepath.Join(cfg.AppsRoot, app, luciPkg)),
			Remote: filepath.ToSlash(filepath.Join("nas-packages-luci", "luci", luciPkg)),
		}}
	} else if dirExists(filepath.Join(actionsRoot, luciPkg)) {
		m.Luci = []Pair{{
			Local:  filepath.ToSlash(filepath.Join(cfg.AppsRoot, app, luciPkg)),
			Remote: filepath.ToSlash(filepath.Join("openwrt-app-actions", "applications", luciPkg)),
		}}
	}

	// meta: openwrt-app-meta is authoritative.
	metaPkg := "app-meta-" + app
	missingMeta := true
	if dirExists(filepath.Join(metaRoot, metaPkg)) {
		m.Meta = []Pair{{
			Local:  filepath.ToSlash(filepath.Join(cfg.AppsRoot, app, metaPkg)),
			Remote: filepath.ToSlash(filepath.Join("openwrt-app-meta", "applications", metaPkg)),
		}}
		missingMeta = false
	}

	return m, missingMeta
}

func dirExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.IsDir()
}

