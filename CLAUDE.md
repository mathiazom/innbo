# Working on this repo

## Slice workflow

Every feature slice goes through four distinct steps, in order:

1. **Grill** — use the `grilling` skill to interview the user and settle
   the slice's design (scope, edge cases, UI/data shape) via
   `AskUserQuestion`, round by round, until the frontier of open
   decisions is empty.
2. **Plan** — a separate, visible checkpoint. Once grilling settles the
   design, call `EnterPlanMode` and present the concrete implementation
   plan (files touched, migration/schema shape, UI changes, etc.).
   **Wait for explicit approval before writing or editing any file.**
   A settled design from grilling is not a plan — don't collapse the two
   and jump straight to `Write`/`Edit` calls once grilling ends.
3. **Implement** — build it, run the repo's own build/format/lint/test
   commands (`gofmt`, `golangci-lint`, `go test`, `dart format`,
   `flutter analyze`) before considering it done.
4. **Review** — run the `code-review` skill (Standards + Spec axes) on
   the diff before treating the slice as finished.

Only skip a step if the user explicitly says to for that specific slice.
