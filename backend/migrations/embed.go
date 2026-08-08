// Package migrations embeds the plain, sequential SQL migration files in
// this directory (no migration framework — see ADR-0004) so the server
// binary can apply them itself on startup.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
