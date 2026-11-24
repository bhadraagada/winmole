// Package reportdispatch recognizes only CLI forms that unambiguously request a JSON report.
package reportdispatch

import "strings"

type Kind int

const (
	Analyze Kind = iota + 1
	Status
)

type Request struct {
	Kind Kind
	Path string
}

// Parse recognizes the existing standalone JSON switch, with a single optional
// analyzer path. Everything else belongs to the legacy command router.
func Parse(args []string) (Request, bool) {
	if len(args) < 2 {
		return Request{}, false
	}

	var request Request
	switch strings.ToLower(args[0]) {
	case "analyze":
		request.Kind = Analyze
	case "status":
		request.Kind = Status
	default:
		return Request{}, false
	}

	hasJSON, hasPath := false, false
	for _, arg := range args[1:] {
		switch strings.ToLower(arg) {
		case "-json", "--json":
			hasJSON = true
			continue
		}

		if request.Kind != Analyze || hasPath {
			return Request{}, false
		}
		path, ok := analyzerPath(arg)
		if !ok {
			return Request{}, false
		}
		request.Path, hasPath = path, true
	}
	if !hasJSON {
		return Request{}, false
	}
	return request, true
}

func analyzerPath(arg string) (string, bool) {
	path := arg
	if strings.HasPrefix(arg, "-") {
		// The existing PowerShell router supports named values only when
		// joined with ':' or '='. Leave other option shapes to that router.
		option, value, ok := strings.Cut(arg, "=")
		if colon := strings.IndexByte(arg, ':'); colon >= 0 && (!ok || colon < len(option)) {
			option, value, ok = arg[:colon], arg[colon+1:], true
		}
		if !ok || value == "" {
			return "", false
		}
		switch strings.ToLower(option) {
		case "-path", "--path":
			path = value
		default:
			return "", false
		}
	}
	// The legacy router strips leading/trailing quotes and supports PowerShell
	// provider syntax. Limit native routing to unambiguous filesystem paths.
	if path != strings.Trim(path, "'`\"") {
		return "", false
	}
	if colon := strings.IndexByte(path, ':'); colon >= 0 {
		isDrive := colon == 1 && ((path[0] >= 'a' && path[0] <= 'z') || (path[0] >= 'A' && path[0] <= 'Z'))
		// Drive-relative paths and PowerShell provider paths may resolve
		// differently outside PowerShell. Keep them on the legacy route.
		if !isDrive || len(path) < 3 || (path[2] != '\\' && path[2] != '/') || strings.Contains(path[2:], ":") {
			return "", false
		}
	}
	return path, true
}
