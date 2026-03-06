package syncapps

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

var ErrRsyncNotFound = errors.New("rsync not found")

type Options struct {
	Slots     []string // services|luci|meta
	Direction string   // both|push|pull
	DryRun    bool
	Delete    bool
}

type slotName string

const (
	slotServices slotName = "services"
	slotLuci     slotName = "luci"
	slotMeta     slotName = "meta"
)

func Sync(cfg *Config, appsFilter []string, opts Options) error {
	if _, err := exec.LookPath(cfg.Rsync.Bin); err != nil {
		return fmt.Errorf("%w: %s", ErrRsyncNotFound, cfg.Rsync.Bin)
	}

	direction, err := parseDirection(opts.Direction)
	if err != nil {
		return err
	}

	wantSlots, err := parseSlots(opts.Slots)
	if err != nil {
		return err
	}

	apps, err := selectApps(cfg, appsFilter)
	if err != nil {
		return err
	}

	baseArgs := []string{"-a", "--update", "--itemize-changes"}
	if opts.DryRun {
		baseArgs = append(baseArgs, "--dry-run")
	}
	if opts.Delete {
		baseArgs = append(baseArgs, "--delete")
	}
	for _, ex := range cfg.Rsync.Excludes {
		ex = strings.TrimSpace(ex)
		if ex == "" {
			continue
		}
		baseArgs = append(baseArgs, "--exclude", ex)
	}
	for _, exf := range cfg.Rsync.ExcludeFiles {
		exf = strings.TrimSpace(exf)
		if exf == "" {
			continue
		}
		if !filepath.IsAbs(exf) {
			exf = filepath.Join(cfg.repoRootAbs, exf)
		}
		baseArgs = append(baseArgs, "--exclude-from", exf)
	}

	var warnCount int
	var syncCount int

	for _, appName := range apps {
		appCfg := cfg.Apps[appName]
		fmt.Printf("\n-- app: %s --\n", appName)

		if wantSlots[slotServices] {
			n, w, err := syncSlot(cfg, cfg.Rsync.Bin, baseArgs, appName, slotServices, appCfg.Services, direction)
			if err != nil {
				return err
			}
			syncCount += n
			warnCount += w
		}
		if wantSlots[slotLuci] {
			n, w, err := syncSlot(cfg, cfg.Rsync.Bin, baseArgs, appName, slotLuci, appCfg.Luci, direction)
			if err != nil {
				return err
			}
			syncCount += n
			warnCount += w
		}
		if wantSlots[slotMeta] {
			n, w, err := syncSlot(cfg, cfg.Rsync.Bin, baseArgs, appName, slotMeta, appCfg.Meta, direction)
			if err != nil {
				return err
			}
			syncCount += n
			warnCount += w
		}
	}

	fmt.Printf("\n== done ==\nrsync runs: %d\nwarnings : %d\n", syncCount, warnCount)
	return nil
}

type directionMode int

const (
	dirBoth directionMode = iota
	dirPush
	dirPull
)

func parseDirection(s string) (directionMode, error) {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "", "both":
		return dirBoth, nil
	case "push":
		return dirPush, nil
	case "pull":
		return dirPull, nil
	default:
		return 0, fmt.Errorf("invalid --direction: %q (want both|push|pull)", s)
	}
}

func parseSlots(slots []string) (map[slotName]bool, error) {
	want := map[slotName]bool{
		slotServices: true,
		slotLuci:     true,
		slotMeta:     true,
	}
	if len(slots) == 0 {
		return want, nil
	}
	want = map[slotName]bool{}
	for _, s := range slots {
		switch strings.ToLower(strings.TrimSpace(s)) {
		case "services":
			want[slotServices] = true
		case "luci":
			want[slotLuci] = true
		case "meta":
			want[slotMeta] = true
		default:
			return nil, fmt.Errorf("invalid --slot: %q (want services|luci|meta)", s)
		}
	}
	return want, nil
}

func selectApps(cfg *Config, filter []string) ([]string, error) {
	if len(filter) == 0 {
		var names []string
		for name := range cfg.Apps {
			names = append(names, name)
		}
		sort.Strings(names)
		return names, nil
	}

	seen := map[string]bool{}
	var out []string
	for _, name := range filter {
		name = strings.TrimSpace(name)
		if name == "" || seen[name] {
			continue
		}
		if _, ok := cfg.Apps[name]; !ok {
			return nil, fmt.Errorf("app not found in config: %s", name)
		}
		seen[name] = true
		out = append(out, name)
	}
	sort.Strings(out)
	return out, nil
}

func syncSlot(cfg *Config, rsyncBin string, baseArgs []string, appName string, slot slotName, pairs []Pair, dir directionMode) (syncCount int, warnCount int, err error) {
	if len(pairs) == 0 {
		return 0, 0, nil
	}

	for i, p := range pairs {
		localAbs, err := cfg.resolveLocal(p.Local)
		if err != nil {
			return syncCount, warnCount, fmt.Errorf("%s/%s pair[%d]: %w", appName, slot, i, err)
		}
		remoteAbs, err := cfg.resolveRemote(p.Remote)
		if err != nil {
			return syncCount, warnCount, fmt.Errorf("%s/%s pair[%d]: %w", appName, slot, i, err)
		}

		fmt.Printf("slot=%s pair=%d\n  local : %s\n  remote: %s\n", slot, i, localAbs, remoteAbs)

		switch dir {
		case dirPush:
			n, w, err := runRsyncOneWay(rsyncBin, baseArgs, localAbs, remoteAbs, false)
			syncCount += n
			warnCount += w
			if err != nil {
				return syncCount, warnCount, err
			}
		case dirPull:
			n, w, err := runRsyncOneWay(rsyncBin, baseArgs, remoteAbs, localAbs, true)
			syncCount += n
			warnCount += w
			if err != nil {
				return syncCount, warnCount, err
			}
		case dirBoth:
			// Prefer pull-first when local doesn't exist (first-time population).
			if _, err := os.Stat(localAbs); err != nil {
				n, w, err := runRsyncOneWay(rsyncBin, baseArgs, remoteAbs, localAbs, true)
				syncCount += n
				warnCount += w
				if err != nil {
					return syncCount, warnCount, err
				}
				n, w, err = runRsyncOneWay(rsyncBin, baseArgs, localAbs, remoteAbs, false)
				syncCount += n
				warnCount += w
				if err != nil {
					return syncCount, warnCount, err
				}
				continue
			}

			n, w, err := runRsyncOneWay(rsyncBin, baseArgs, localAbs, remoteAbs, false)
			syncCount += n
			warnCount += w
			if err != nil {
				return syncCount, warnCount, err
			}
			n, w, err = runRsyncOneWay(rsyncBin, baseArgs, remoteAbs, localAbs, true)
			syncCount += n
			warnCount += w
			if err != nil {
				return syncCount, warnCount, err
			}
		default:
			return syncCount, warnCount, fmt.Errorf("unknown direction mode")
		}
	}
	return syncCount, warnCount, nil
}

func runRsyncOneWay(rsyncBin string, baseArgs []string, srcDir string, dstDir string, warnOnMissingSrc bool) (syncCount int, warnCount int, err error) {
	if st, statErr := os.Stat(srcDir); statErr != nil || !st.IsDir() {
		if warnOnMissingSrc {
			fmt.Printf("  warn: missing src dir, skip: %s\n", srcDir)
			return 0, 1, nil
		}
		fmt.Printf("  skip: missing src dir: %s\n", srcDir)
		return 0, 0, nil
	}
	if err := os.MkdirAll(dstDir, 0o775); err != nil {
		return 0, 0, err
	}

	src := ensureTrailingSep(srcDir)
	dst := ensureTrailingSep(dstDir)

	args := append([]string{}, baseArgs...)
	args = append(args, src, dst)

	fmt.Printf("  rsync: %s %s\n", rsyncBin, strings.Join(args, " "))
	cmd := exec.Command(rsyncBin, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return 1, 0, err
	}
	return 1, 0, nil
}

func ensureTrailingSep(p string) string {
	if strings.HasSuffix(p, string(os.PathSeparator)) {
		return p
	}
	return p + string(os.PathSeparator)
}
