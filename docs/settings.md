---
title: "Mac Capture settings"
description: "Settings window controls, defaults, and linked pages for Bob, hotkeys, Refs, agenda, similar tasks, stash, templates, launch, notifications, and diagnostics."
---

The Settings window is a 560 pt form. Section order matches `SettingsView`: Bob, Hotkey, References, Agenda, Similar Tasks, Canceled Draft Stash, Saved Templates, Launch, Notifications, Diagnostics. The app owns these controls. Capture grammar, template capacity, and vault mutation stay in `bob` ([thin client decision](https://bobs-org.github.io/develop/decisions/#mac-capture-is-a-thin-client)). Values persist in `UserDefaults` under `org.bobs.bob-mac-capture` unless noted as transient.

Install identity and executable search are in [Install](install.md). Permission grants are in [Permissions](permissions.md). Panel keys are in [Keyboard](keyboard.md). Refs behavior is in [Bob Refs](refs.md).

## Bob

| Control | Default | Notes |
| --- | --- | --- |
| Executable override | empty | Absolute path to a `bob` executable. Relative paths are refused. The app never uses a login shell to find `bob`. |
| Vault path | empty | Passed to `bob` as the vault root when set. |
| Resolved path | `Not resolved` | Read-only. Recheck Bob from the menu-bar item refreshes it. |

Candidate locations when the override is empty are in [Install](install.md#requirements).

## Hotkey

| Control | Default | Notes |
| --- | --- | --- |
| Use production Control-Shift-Command-I | on | Off selects the development/rollback binding Control-Shift-Command-R. Turn it off only when restoring the retired Hammerspoon capture workflow. |
| Active binding | Control-Shift-Command-I | Read-only display of the live capture chord. |

One Carbon handler (`HotKeyRegistry`, signature `'BOBC'`) owns capture (id 1), Refs (id 2), the Highlights-frontmost open key (id 3), and the Highlights Tabs key (id 4). Each registration is independent: a failed one leaves the others intact. A conflict reports `Hotkey conflict` (or `Refs hotkey conflict: …`) in Diagnostics and Recent Activity. Recovery is in [Resolve a Mac Capture hotkey conflict](https://bobs-org.github.io/guides/resolve-mac-capture-hotkey-conflict/).

## References

| Control | Default | Notes |
| --- | --- | --- |
| Open Bob Refs with Control-Shift-Command-O | on | Global Refs toggle. Off unregisters that chord. |
| Preview highlights per page | 5 | Range 1–20 (`RefsNotesPage.sizeRange`). Control-D at the bottom of the inspector preview shows this many more. Also `defaults write org.bobs.bob-mac-capture refsInspectorNotesPageSize -int 5`. |
| In Highlights, open Bob Refs with | Command-O | `Off`, `Command-O`, or `Control-O`. Registers only while Highlights or the override app is frontmost. Highlights' File › Open… keeps its own dialog. |
| In Highlights, show open tabs with | Command-T | `Command-T`, `Shift-Command-O`, `Command-E`, or `Off`. Registers only for Highlights or the override app. Command-T steps aside while Bob Refs is visible so its in-panel Tabs toggle works. |
| Highlights app | resolved name, version, and path, or `Not found` | Choose… is limited to `.app`. Use Default clears the override path. |
| Tell me when Bob updates an open PDF | on | Off suppresses notifications only; footer clauses stay. Caption: "Bob asks Highlights to save your unsaved highlights first; Highlights then reloads the PDF in place." |
| Scan after ⌘S in Highlights | on | Observes Command-S passively and scans after a library PDF save settles. Shows "Needs Accessibility" when needed; Settings never prompts. |
| Highlights tabs | `Allowed` / `Not allowed` | Live Accessibility grant for reading Highlights tabs. Never prompts from Settings. Ad-hoc builds caption: "Grants reset when an ad-hoc build is reinstalled." |
| Reset Open History… | — | Confirmed. Clears recently-opened rows and frecency. Disabled when no reset handler is installed. |

Toggling these controls re-registers the Refs bindings immediately. Opening, Tabs, inspector paging, and open-PDF update notices are in [Bob Refs](refs.md) and [Bob Refs inspector](refs-inspector.md).

## Agenda

| Control | Default | Notes |
| --- | --- | --- |
| Show today's Pomodoros when the draft is empty | on | Off hides the idle agenda. |
| Agenda status | empty | Transient. Never persisted. Shows strings such as "Last refreshed 14:32", a refresh failure, or an old-bob hint. |

Agenda facts come from `bob capture-pomodoros --tasks`. Layout and folding are in [Idle agenda](idle-agenda.md).

## Similar Tasks

| Control | Default | Notes |
| --- | --- | --- |
| Show similar tasks while capturing | on | Shows Bob's similar-task matches after a 350 ms pause. The band stays hidden when `bob` does not support `capture-related`; capture behavior is unchanged. |

Matching and the JSON contract belong to `bob capture-related`; the Mac app owns the settle delay and row presentation. See [Protocol](protocol.md#optional-commands) and [Capture previews](capture-previews.md).

## Canceled Draft Stash

| Control | Default | Notes |
| --- | --- | --- |
| Capacity | 10 | Range 0–36. 0 turns stashing off and deletes the stash file. |
| Retained | live count | Read-only. |
| Clear Stash... | — | Confirmed. Permanently removes retained canceled drafts. Disabled when the stash is empty. |

Canceled drafts live on disk and survive quit and restart. Capacity 0 or Clear Stash... deletes the file. Storage rules are in [Permissions](permissions.md). Stash keys are in [Keyboard](keyboard.md) and [Capture panel](capture-panel.md).

## Saved Templates

This section reports `bob capture-templates` state. It does not expose `capture.max_saved_templates` as an in-app control; that key stays in CLI configuration. While the shelf is available it shows the saved count, the capacity, a "Saving is off" caption when `capture.max_saved_templates` is 0, the file path, Reveal in Finder, and confirmed **Clear Templates…** (also removes the quarantine copy). Loading, a list failure, or an older `bob` that lacks `capture-templates` show a caption instead of the count. Clear is disabled when the shelf is empty, unsupported, or a clear is already in flight.

Shelf behavior is in [Saved templates](saved-templates.md).

## Launch

| Control | Default | Notes |
| --- | --- | --- |
| Launch at login | macOS `SMAppService` state | Registers or unregisters `SMAppService.mainApp`. |
| Status | `Enabled`, `Requires approval in System Settings`, `Not registered`, `App bundle not found`, or `Unknown` | Read-only. |

The app cannot grant Login Items approval for itself. Recovery is in [Permissions](permissions.md#launch-at-login).

## Notifications

| Control | Notes |
| --- | --- |
| Authorization | Live status: `Not requested`, `Denied — enable in System Settings`, `Authorized`, `Provisional`, `Ephemeral`, or `Unknown`. |
| Enable Notifications | Shown only while authorization can still be requested. |
| Open System Notification Settings | Opens the system notifications pane. |
| Send Test Notification | Writes `Test notification sent` or `Test notification failed: …`. |

Capture correctness never depends on notifications. Delivery and authorization persistence require the installed signed bundle; Settings › Diagnostics shows the signing state. Notification copy, the install-complete banner, and the open action are in [Notifications](#notification-copy). Open-PDF update notices are in [Bob Refs](refs.md#open-pdfs-in-highlights). Authorization storage is in [Permissions](permissions.md#notifications).

### Notification copy

The app posts success and failure `UNUserNotificationCenter` notifications. Success notifications use Bob's semantic capture text rather than raw draft syntax: a single capture is titled `Task captured` or `Note captured`, names the destination, and includes scheduled-date metadata when Bob returns it. A close is titled `Closed NAME` and its body carries the session and timing line, the tasks and Work Log line, and the next-session line. A start is titled `Started NAME` with the session and queued-task count; a restart is titled `Restarted NAME` with the en-dash session, queued count, and ` · was 0920–0945`, and a swap is titled `Swapped in NAME` with the taken range and the demoted session back to first future. A batch is titled with the item count, summarizes task/note and destination counts, and emits one ordered body line per captured item without substituting an ellipsis for later entries. Close batch lines append ` (closed NAME)` and count under a `Close` kind; start batch lines append ` (started NAME …)`, ` (restarted NAME …)`, or ` (swapped in NAME …)` under a `Start` kind. When Bob reports a global destination, a same-scope batch uses compact wording such as `2 tasks · foo.md` or `2 notes · file.md · under ^a-id`; only items that locally override the global declaration repeat their actual destination. The raw `@@...` declaration is never included in notification text. The only newly authorized notification body content is the captured semantic text; failure notifications still carry only the bounded error message. The install-complete banner uses fixed copy with no path, identity, version, or capture text.

Capture notifications register a foreground action named for the note count and store Bob's open-plan payload. Clicking the notification or pressing its open action sends one `bob-open-notes` URL. Older delivered notifications still route from their `targetPath` or `targetPaths` values. If Bob reports no usable destination, the notification remains informative and omits the open action. Control-Return posts the same capture-success notification as Return, then opens the notes in Obsidian. If the open fails, a second notification, "Captured, but Obsidian didn't open", carries the error.

When `just install` restarts a copy that was already running, the replacement process posts one native completion notification after it finishes launching:

- title: `Install complete`
- body: `Bob Mac Capture restarted successfully.`
- sound: the default notification sound
- action: `Capture`

Clicking the banner or choosing `Capture` opens the capture panel; dismissing it does nothing. The banner is confirmation that the replacement process itself reached a usable launch point, not that the install helper merely asked LaunchServices to open the bundle. It is requested only for that one-shot install-triggered restart, and only when macOS already allows notifications for the signed bundle. An install never prompts for notification permission. Denied or not-yet-requested authorization is silent and non-fatal: the replacement still launches. A stopped install does not launch the app and does not notify. `menu-bar icon → Restart Bob Mac Capture` is a manual relaunch, not an install completion, and does not show this banner.

## Diagnostics

| Row | Notes |
| --- | --- |
| Status | Selectable current `diagnosticStatus` string (starts as `Starting`). |
| Signing | Live `signingDiagnostic` (`Not checked` until inspected). |
| Recent activity | Disclosure of the last 20 timestamped status strings (`HH:mm:ss`), metadata only. |

Signposts, timeouts, Copy Diagnostic, menu-bar icon states, and `refs-rank` are in [Diagnostics](diagnostics.md).
