package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

type App struct {
	ID            string   `json:"id"`
	Title         string   `json:"title,omitempty"`
	Description   string   `json:"description,omitempty"`
	DescriptionEn string   `json:"description_en,omitempty"`
	Tags          []string `json:"tags,omitempty"`
	Website       string   `json:"website,omitempty"`
	Author        string   `json:"author,omitempty"`
	Version       string   `json:"version,omitempty"`
	Release       string   `json:"release,omitempty"`
	Depends       string   `json:"depends,omitempty"`
	LuciEntry     string   `json:"luci_entry,omitempty"`
	MetaDir       string   `json:"meta_dir,omitempty"`
}

var (
	assignRe = regexp.MustCompile(`^\s*([A-Za-z0-9_.-]+)\s*(?::=|=)\s*(.*?)\s*$`)
)

func parseMakefileVars(path string) (map[string]string, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	lines := strings.Split(string(b), "\n")
	vars := make(map[string]string, 32)

	for _, raw := range lines {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		m := assignRe.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		key := m[1]
		val := strings.TrimSpace(m[2])
		vars[key] = val
	}
	return vars, nil
}

func splitTags(s string) []string {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil
	}
	parts := strings.Fields(s)
	var out []string
	seen := make(map[string]bool, len(parts))
	for _, p := range parts {
		if !seen[p] {
			seen[p] = true
			out = append(out, p)
		}
	}
	sort.Strings(out)
	return out
}

func main() {
	var (
		appsRoot  string
		outJSON   string
		outMDMin  string
		outMDFull string
	)

	flag.StringVar(&appsRoot, "apps-root", "apps", "apps root (default: apps)")
	flag.StringVar(&outJSON, "out-json", "docs/apps-catalog.json", "output JSON path")
	flag.StringVar(&outMDMin, "out-md", "docs/apps-catalog.min.md", "output minimal Markdown path")
	flag.StringVar(&outMDFull, "out-md-full", "docs/apps-catalog.md", "output full Markdown path")
	flag.Parse()

	appsRoot = filepath.Clean(appsRoot)

	appByID := map[string]*App{}
	var ids []string

	err := filepath.WalkDir(appsRoot, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() {
			return nil
		}
		if filepath.Base(path) != "Makefile" {
			return nil
		}

		metaDir := filepath.Base(filepath.Dir(path))
		if !strings.HasPrefix(metaDir, "app-meta-") {
			return nil
		}

		id := strings.TrimPrefix(metaDir, "app-meta-")
		if strings.TrimSpace(id) == "" {
			return nil
		}

		vars, err := parseMakefileVars(path)
		if err != nil {
			return fmt.Errorf("parse %s: %w", path, err)
		}

		a, ok := appByID[id]
		if !ok {
			a = &App{ID: id}
			appByID[id] = a
			ids = append(ids, id)
		}

		a.MetaDir = filepath.ToSlash(filepath.Dir(path))
		a.Title = firstNonEmpty(a.Title, vars["META_TITLE"])
		a.Description = firstNonEmpty(a.Description, vars["META_DESCRIPTION"])
		a.DescriptionEn = firstNonEmpty(a.DescriptionEn, vars["META_DESCRIPTION.en"])
		a.Website = firstNonEmpty(a.Website, vars["META_WEBSITE"])
		a.Author = firstNonEmpty(a.Author, vars["META_AUTHOR"])
		a.Version = firstNonEmpty(a.Version, vars["PKG_VERSION"])
		a.Release = firstNonEmpty(a.Release, vars["PKG_RELEASE"])
		a.Depends = firstNonEmpty(a.Depends, vars["META_DEPENDS"])
		a.LuciEntry = firstNonEmpty(a.LuciEntry, vars["META_LUCI_ENTRY"])
		if len(a.Tags) == 0 {
			a.Tags = splitTags(vars["META_TAGS"])
		}

		return nil
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}

	sort.Strings(ids)

	var apps []*App
	for _, id := range ids {
		apps = append(apps, appByID[id])
	}

	if err := writeJSON(outJSON, apps); err != nil {
		fmt.Fprintln(os.Stderr, "error: write json:", err)
		os.Exit(1)
	}
	if err := writeMDMin(outMDMin, apps); err != nil {
		fmt.Fprintln(os.Stderr, "error: write md:", err)
		os.Exit(1)
	}
	if err := writeMDFull(outMDFull, apps); err != nil {
		fmt.Fprintln(os.Stderr, "error: write full md:", err)
		os.Exit(1)
	}
}

func firstNonEmpty(existing, candidate string) string {
	if strings.TrimSpace(existing) != "" {
		return existing
	}
	return strings.TrimSpace(candidate)
}

func writeJSON(path string, apps []*App) error {
	b, err := json.MarshalIndent(apps, "", "  ")
	if err != nil {
		return err
	}
	b = append(b, '\n')
	return writeFileWithDirs(path, b)
}

func writeMDMin(path string, apps []*App) error {
	var sb strings.Builder
	sb.WriteString("# Apps Catalog (minimal)\n\n")
	sb.WriteString("Auto-generated from `apps/*/app-meta-*/Makefile` via `make apps-catalog`.\n\n")
	sb.WriteString("Format: `id — title — description`\n\n")
	for _, a := range apps {
		title := a.Title
		if title == "" {
			title = a.ID
		}
		desc := a.Description
		if desc == "" {
			desc = a.DescriptionEn
		}
		desc = strings.ReplaceAll(desc, "\n", " ")
		desc = strings.TrimSpace(desc)
		if desc != "" {
			sb.WriteString(fmt.Sprintf("- %s — %s — %s\n", a.ID, title, desc))
		} else {
			sb.WriteString(fmt.Sprintf("- %s — %s\n", a.ID, title))
		}
	}
	return writeFileWithDirs(path, []byte(sb.String()))
}

func writeMDFull(path string, apps []*App) error {
	var sb strings.Builder
	sb.WriteString("# Apps Catalog\n\n")
	sb.WriteString("Auto-generated from `apps/*/app-meta-*/Makefile` via `make apps-catalog`.\n\n")
	sb.WriteString("| id | title | tags | luci | website | description |\n")
	sb.WriteString("|---|---|---|---|---|---|\n")
	for _, a := range apps {
		title := escapeMD(a.Title)
		if title == "" {
			title = escapeMD(a.ID)
		}
		desc := a.Description
		if desc == "" {
			desc = a.DescriptionEn
		}
		row := []string{
			escapeMD(a.ID),
			title,
			escapeMD(strings.Join(a.Tags, " ")),
			escapeMD(a.LuciEntry),
			escapeMD(a.Website),
			escapeMD(desc),
		}
		sb.WriteString("| " + strings.Join(row, " | ") + " |\n")
	}
	return writeFileWithDirs(path, []byte(sb.String()))
}

func escapeMD(s string) string {
	s = strings.ReplaceAll(s, "\n", " ")
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, "|", `\|`)
	return s
}

func writeFileWithDirs(path string, content []byte) error {
	dir := filepath.Dir(path)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0o775); err != nil {
			return err
		}
	}
	return os.WriteFile(path, content, 0o664)
}
