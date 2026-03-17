package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

type FileEntry struct {
	Name    string    `json:"name"`
	Size    int64     `json:"size"`
	ModTime time.Time `json:"modTime"`
	IsDir   bool      `json:"isDir"`
}

func main() {
	addr := flag.String("addr", ":8080", "listen address")
	filesDirFlag := flag.String("files", "", "directory to list (defaults to auto-detect)")
	webDirFlag := flag.String("web", "", "directory to serve UI from (defaults to auto-detect)")
	flag.Parse()

	filesDir := strings.TrimSpace(firstNonEmpty(*filesDirFlag, os.Getenv("FILES_DIR")))
	if filesDir == "" {
		filesDir = firstExistingDir("go-server/files", "files")
	}
	if filesDir == "" {
		log.Fatal("could not find files directory; set -files or FILES_DIR")
	}

	webDir := strings.TrimSpace(firstNonEmpty(*webDirFlag, os.Getenv("WEB_DIR")))
	if webDir == "" {
		webDir = firstExistingDir("file-web", "../file-web")
	}

	mux := http.NewServeMux()

	mux.HandleFunc("/api/files", func(w http.ResponseWriter, r *http.Request) {
		switch r.Method {
		case http.MethodOptions:
			writeCORSHeaders(w)
			w.WriteHeader(http.StatusNoContent)
			return
		case http.MethodGet:
		default:
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		allowHidden := parseBool(r.URL.Query().Get("hidden"))
		writeCORSHeaders(w)
		w.Header().Set("Content-Type", "application/json; charset=utf-8")

		list, err := listDir(filesDir, allowHidden)
		if err != nil {
			http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
			return
		}

		enc := json.NewEncoder(w)
		enc.SetIndent("", "  ")
		if err := enc.Encode(list); err != nil {
			http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
			return
		}
	})

	if webDir != "" {
		mux.Handle("/", http.FileServer(http.Dir(webDir)))
	}

	log.Printf("list dir: %s", filesDir)
	if webDir != "" {
		log.Printf("web dir:  %s", webDir)
	} else {
		log.Printf("web dir:  (disabled)")
	}
	log.Printf("listening on %s", *addr)
	log.Fatal(http.ListenAndServe(*addr, logRequests(mux)))
}

func listDir(dir string, allowHidden bool) ([]FileEntry, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}

	out := make([]FileEntry, 0, len(entries))
	for _, entry := range entries {
		name := entry.Name()
		if !allowHidden && strings.HasPrefix(name, ".") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			return nil, err
		}

		out = append(out, FileEntry{
			Name:    name,
			Size:    info.Size(),
			ModTime: info.ModTime(),
			IsDir:   info.IsDir(),
		})
	}

	sort.Slice(out, func(i, j int) bool {
		if out[i].IsDir != out[j].IsDir {
			return out[i].IsDir
		}
		return strings.ToLower(out[i].Name) < strings.ToLower(out[j].Name)
	})

	return out, nil
}

func parseBool(v string) bool {
	if v == "" {
		return false
	}
	if b, err := strconv.ParseBool(v); err == nil {
		return b
	}
	return v == "1" || strings.EqualFold(v, "yes") || strings.EqualFold(v, "y")
}

func writeCORSHeaders(w http.ResponseWriter) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
	w.Header().Set("Access-Control-Max-Age", "86400")
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s (%s)", r.Method, r.URL.Path, time.Since(start).Truncate(time.Millisecond))
	})
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}

func firstExistingDir(candidates ...string) string {
	for _, candidate := range candidates {
		if candidate == "" {
			continue
		}
		path := filepath.Clean(candidate)
		if fi, err := os.Stat(path); err == nil && fi.IsDir() {
			return path
		}
	}
	return ""
}
