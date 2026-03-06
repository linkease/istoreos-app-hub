package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"strings"

	"github.com/linkease/istoreos-app-hub/tools/internal/syncapps"
)

type multiFlag []string

func (m *multiFlag) String() string { return strings.Join(*m, ",") }
func (m *multiFlag) Set(v string) error {
	*m = append(*m, v)
	return nil
}

func usage() {
	fmt.Fprint(os.Stderr, `syncapps - bidirectional rsync sync for istoreos-app-hub

Usage:
  syncapps --config syncapps.yaml --all [--dry-run]
  syncapps --config syncapps.yaml --app istorepanel [--slot meta] [--dry-run]

Options:
  --config <path>        Config YAML (default: syncapps.yaml)
  --all                  Sync all apps in config
  --app <name>           Sync one app (repeatable)
  --slot <services|luci|meta>  Sync only a slot (repeatable)
  --direction <both|push|pull> Default: both
  --dry-run              Pass --dry-run to rsync
  --delete               Pass --delete to rsync (dangerous)
  --list                 List apps and exit
`)
}

func main() {
	var (
		configPath string
		all        bool
		apps       multiFlag
		slots      multiFlag
		direction  string
		dryRun     bool
		deleteFlag bool
		listOnly   bool
	)

	flag.StringVar(&configPath, "config", "syncapps.yaml", "config path")
	flag.BoolVar(&all, "all", false, "sync all apps")
	flag.Var(&apps, "app", "sync one app (repeatable)")
	flag.Var(&slots, "slot", "sync only a slot (repeatable)")
	flag.StringVar(&direction, "direction", "both", "both|push|pull")
	flag.BoolVar(&dryRun, "dry-run", false, "dry-run")
	flag.BoolVar(&deleteFlag, "delete", false, "rsync --delete")
	flag.BoolVar(&listOnly, "list", false, "list apps")
	flag.Usage = usage
	flag.Parse()

	cfg, err := syncapps.LoadConfig(configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error: load config:", err)
		os.Exit(2)
	}

	if listOnly {
		for _, item := range syncapps.ListApps(cfg) {
			fmt.Println(item)
		}
		return
	}

	if !all && len(apps) == 0 {
		usage()
		fmt.Fprintln(os.Stderr, "error: must pass --all or at least one --app")
		os.Exit(2)
	}

	opts := syncapps.Options{
		Direction: direction,
		DryRun:    dryRun,
		Delete:    deleteFlag,
	}

	if len(slots) > 0 {
		opts.Slots = slots
	}

	var appFilter []string
	if !all {
		appFilter = apps
	}

	if err := syncapps.Sync(cfg, appFilter, opts); err != nil {
		if errors.Is(err, syncapps.ErrRsyncNotFound) {
			fmt.Fprintln(os.Stderr, "error:", err)
			fmt.Fprintln(os.Stderr, "hint: install rsync or set `rsync.bin` in syncapps.yaml")
			os.Exit(127)
		}
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
