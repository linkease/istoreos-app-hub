package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/linkease/istoreos-app-hub/tools/internal/syncapps"
)

func usage() {
	fmt.Fprint(os.Stderr, `syncapps-autogen - populate syncapps.yaml by scanning legacy repos

Usage:
  syncapps-autogen --config syncapps.yaml

Options:
  --config <path>   Config YAML to update (default: syncapps.yaml)
  --force           Overwrite existing mappings for discovered apps
  --dry-run         Print summary only, do not write file
`)
}

func main() {
	var (
		configPath string
		force      bool
		dryRun     bool
	)
	flag.StringVar(&configPath, "config", "syncapps.yaml", "config path")
	flag.BoolVar(&force, "force", false, "overwrite existing mappings")
	flag.BoolVar(&dryRun, "dry-run", false, "dry-run")
	flag.Usage = usage
	flag.Parse()

	cfg, err := syncapps.LoadConfig(configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error: load config:", err)
		os.Exit(2)
	}

	sum, err := syncapps.Autogen(cfg, syncapps.AutogenOptions{Force: force})
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}

	fmt.Printf("discovered apps : %d\n", sum.DiscoveredApps)
	fmt.Printf("updated apps    : %d\n", sum.UpdatedApps)
	fmt.Printf("missing meta    : %d\n", len(sum.MissingMetaApps))
	if len(sum.MissingMetaApps) > 0 {
		fmt.Println("missing meta list:")
		for _, a := range sum.MissingMetaApps {
			fmt.Println(" -", a)
		}
	}

	if dryRun {
		return
	}

	if err := syncapps.SaveConfig(configPath, cfg); err != nil {
		fmt.Fprintln(os.Stderr, "error: write config:", err)
		os.Exit(1)
	}
}

