# Task-theme fixtures (phase mac-capture)

These four fixtures exercise the additive task-theme JSON Bob reports for
phase `mac-capture` (`bob-cli-dm.8`). All keys match the Rust serialization
exactly:

- `capture-complete-theme-suggestion.json` — `CaptureCompletionResponse`
  with top-level `theme_suggestion` and one `suggested` + `suggestion_label`
  row (`src/native/capture_complete/model.rs`,
  `src/native/pomodoro_themes/preselect.rs`, `src/native/pomodoro_themes/suggest.rs`).
- `capture-task-theme-set.json` — `CaptureCommandResponse` success item with
  `task_theme: {action: set, theme, previous, inherited}`
  (`src/native/capture/output.rs` `CaptureTaskThemeChange`).
- `refs-today-theme-suggestion.json` — `bob ref today` listing with
  `theme_suggestion` and one suggested row
  (`src/native/ref_library/today.rs`, `src/native/capture/existing_task_link.rs`
  `TodayPomodoroRow` plus the additive `suggested`/`suggestion_label`).
- `refs-today-theme-create.json` — listing with
  `theme_suggestion.create: true` for a reading task
  (`MenuSuggestion::new` with `MenuChoice::Create`).

## Provenance

Contract-derived in this turn from the Rust structs above (exact wire keys:
`theme_suggestion`, `suggested`, `suggestion_label`, `task_theme`, `create`,
`fallback`, `from.{path,stem,kind,hue,chain}`, `inherited`, `repair`).
The installed `bob 0.4.0` on apollo predates `bob themes suggest` and was
not used; a workspace `bob` build (which carries suggest-core,
complete-suggest, and capture-write) did not fit this single turn, so no
scratch-vault recording was made here. Re-record from a scratch vault with
a temporary `theme:` default when a builder is available and diff against
these files; they must stay byte-compatible with Bob's output.
