---
title: "Mac Capture keyboard"
description: "Every Bob Mac Capture key binding: editor, completion, prompts, stash, shelf, and today's Pomodoro."
---

Successor cards: [Capture previews](capture-previews.md); stash: [Capture panel](capture-panel.md); templates: [Saved templates](saved-templates.md). For global chord conflicts, see [Resolve a Mac Capture hotkey conflict](https://bobs-org.github.io/guides/resolve-mac-capture-hotkey-conflict/).

## Switching panels

Ctrl-Tab and Ctrl-Shift-Tab switch panels, keeping the draft and view.

[Event note bindings](event-notes.md).

## Bob Refs shortcuts

These rows act in the Bob Refs panel; [Bob Refs](refs.md) and [Bob Refs inspector](refs-inspector.md) expand them. Global Control-Shift-Command-O and `Command-]` toggle the panel from any app; see [Opening Bob Refs](refs.md#opening-bob-refs).

| Key | Action |
| --- | --- |
| Command-S (in Highlights) | Scan after the library PDF saves when the setting is on; the key reaches Highlights unchanged |
| Option-N | Mark the selected Ready or Next reference Seen, or New again; the row stays put until the next re-rank; other rows beep |
| Command-T | Toggle the Tabs filter; the query and kind scope stay in place |
| Command-T (in Highlights) | While Highlights is frontmost and Bob Refs is hidden, open Bob Refs in Tabs from fresh defaults with the focused PDF selected; configurable to Shift-Command-O, Command-E, or Off |
| Command-Y | Open the Copy card for the selected row |
| Command-Y (in Highlights) | While Highlights is frontmost and Bob Refs is hidden, open the Copy card on the focused PDF; configurable to Off. Keys typed before the PDF is known replay on the card |
| Command-B | Open the Copy card for the selected row with the code picker pressed |
| Command-L | Open the Copy card for the selected row with the link picker pressed |
| Command-B / Command-L (in Highlights) | Registered while Highlights or its override app is frontmost; opens the code or link picker on the focused PDF, yields while Bob Refs is visible, and can be set to Off. Keys typed before the PDF is known replay on the card |
| Control-Return | Open the reading task's file in Obsidian (at the task line) |
| Ctrl-X | Close the selected tab in Highlights (Tabs only) |
| Ctrl-D | Scroll the preview down by half its height |
| Ctrl-U | Scroll the preview up by half its height |
| Ctrl-C | Reset the query, filters, selection, revealed pages, and scroll positions |
| Escape / Ctrl-[ | Close cards and banners, then the panel while keeping its view |
| Shift-Command-T | Reopen the most recently closed Highlights tab |
| Ctrl-Tab / Ctrl-Shift-Tab | Switch to Capture, keeping the remembered view |

## Copy card keys

While the Copy card is open:

| Key | Action |
| --- | --- |
| C | Open the code picker when the reference has saved Markdown and recorded blocks (Markdown or web page) |
| L | Open the link picker when the reference has saved Markdown and recorded links (Markdown or web page); Option-U copies the Markdown link |
| M | Copy the saved Markdown source; Option-M copies its `~` path |
| 1–9 | Copy the visible note or the picker row matching the keycap currently shown; the hint names that live range |
| Shift-1–9 / Shift-Return | In a link picker, open that visible / selected web link in the default browser |
| Return | Copy the selected row, or open the C, H, or L picker when that row is selected |
| Option-Return | Copy the fenced form of the selected code block, or the Markdown form of the selected link |
| A | In a highlight picker copy all highlights; in a link picker copy every distinct URL (Option-A as a Markdown list) |
| Up / Down | Move the selection (and the code or link preview well) |
| Escape / Ctrl-[ | Return to the card from a picker, then to the inspector |

Command-B Return from Highlights copies the code block on the current page.
Command-L Return copies the link on the current page. Without saved Markdown,
Command-L Shift-Return opens the current page's web link in the default browser.
Without saved Markdown, Command-L copies the reference's Markdown link immediately,
as Command-Y L does.

### When a Highlights copy key fails

- Without Accessibility, Bob Refs shows its existing Tabs permission card.
- With no open PDF, the card says `Highlights has no open document`; an unmatched
  PDF names its filename. A collision says `Two references match “…” — pick one,
  then ⌘B` or `⌘L`.
- A slow tab read says `Highlights didn't answer — try ⌘B again` or `⌘L again`;
  a failed read says `Couldn't read Highlights — ⌘R retries`.
- While catalogs load, the card says `Loading code… esc cancels` or
  `Loading links… esc cancels`. Load failures and unavailable content show the
  Copy card's red reason.
- If another app owns a chord, a warning toast names it and says which copy action
  will not work. Change the key in Bob Settings › References.

## Editor and completion keys

| Key | In the editor | While completion is visible | While Add block ID is open | While Name Pomodoro is open |
| --- | --- | --- | --- | --- |
| Return | Capture, then close the panel | Accept the selected completion; with no selected row, capture the draft as typed | Add the ID and select the task | Name the Pomodoro and select it |
| Control-Return | Capture, open Bob's reported notes on their captured lines, then close the panel | Accept, then capture and open if no picker or prompt follows; no row, capture and open as typed. Relation picker: open the card | Same as Return; keep an open intent from a picker | Same as Return; keep an open intent from a picker |
| Command-Return | Same as Control-Return | Same as Control-Return | Consume the key; do not capture | Consume the key; do not capture |
| Shift-Return / Option-Return | Insert a newline; at the end of a lone `@file` or `@file#section` header that bob's parse reports as needing a `list_item`, insert `\n- ` to start the first bullet | Insert a newline | Add the ID and select the task | Name the Pomodoro and select it |
| Ctrl-J | Insert a new indentation-aware `- ` row; anywhere before a populated dash bullet's body, remove the prefix into a blank separator and keep its body; in a template draft, as reported by bob's parse, insert a plain newline | Same edit, and close completion | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-O | Insert a blank physical line immediately above the current line and move the caret onto it | Same edit, and close completion | Native text-field behavior | Native text-field behavior |
| Ctrl-U | Delete from the caret to the beginning of the current physical line; when the caret is already at that start, delete the previous line instead, stopping on the first line | Same deletion, closing completion | Native text-field behavior | Native text-field behavior |
| Ctrl-G, U | Toggle the current physical line to uppercase, or to lowercase when it is already all uppercase. A multi-line selection uses one direction for every touched line. The caret or selection stays on the same characters, and Command-Z restores the line | Same toggle, closing completion | Native text-field behavior | Native text-field behavior |
| Ctrl-A | Move to physical-line start; there, move to the previous line. Stop at the first | Same move; completion stays open and reanchors | Native text-field behavior | Native text-field behavior |
| Ctrl-E | Move to physical-line end; there, move to the next line. Stop at the last | Same move; completion stays open and reanchors | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-J | Move down one line, keeping column where possible; clamp at short-line end. Stop at the last | Same move; completion stays open and reanchors | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-K | Move up one line, keeping column where possible; clamp at short-line end. Stop at the first | Same move; completion stays open and reanchors | Native text-field behavior | Native text-field behavior |
| Ctrl-L | Move by WORD (vim `W`): a nonblank run or empty line; from the last WORD, move to draft end | Same move; completion stays open and reanchors | Native text-field behavior | Native text-field behavior |
| Ctrl-H | Move by WORD (vim `B`): a nonblank run or empty line; from the first WORD, move to draft start | Same move; completion stays open | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-L | Move by word (vim `w`): keyword, emoji, or punctuation run; from the last word, move to draft end | Same move; completion stays open | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-H | Move by word (vim `b`): keyword, emoji, or punctuation run; from the first word, move to draft start | Same move; completion stays open | Native text-field behavior | Native text-field behavior |
| Command-V | Insert plain clipboard text; on an empty bullet row receiving a Markdown list, consume the first marker and align the list | Same paste edit, and close completion | Native text-field paste | Native text-field paste |
| @ | Insert `@`; Bob may return route completion when the draft declares a global `@@route` | Insert `@` and refresh Bob's completion for the edited draft | Native text-field behavior | Native text-field behavior |
| Backspace | Remove an auto-inserted `,<digit>` pair together, else an unused `- ` row in one action (native Backspace otherwise, including modified Backspace) | Remove an unused `- ` row in one action | Native text-field Backspace | Native text-field Backspace |
| 1–9 | Right after a task number in a close list (`x`, `x*`, `x!` and `*`/`!`/`~` groups, incl. `=x` closes and sized `Nx` closes like `2x1`), insert `,` before the digit (`x1`+`2`→`x1,2`) when the running Pomodoro has under 10 numbered Task Links; else the digit types normally. Typing a digit right after the `x` in `12x` never inserts a comma (the size stays one number) | Native text-field behavior | Native text-field behavior | Native text-field behavior |
| + | Insert `+` | While route completion is visible, right after the completed route: accept it, keep `+`, open task completion | Native text-field behavior | Native text-field behavior |
| , | Insert `,`; where Parent Task completion applies, Bob maps it to `+` (or ` +` after a complete target run); glued to a complete `@route:id` / `@route^id`, switches it to `@route+id` | Empty `+` filter: use Bob's alias; selected row with `continuation`: accept and continue | Native text-field behavior | Native text-field behavior |
| . | After `@route`, `.` → `^` opens Block ID; glued to a complete `@route:id` / `@route^id`, it toggles the separator; glued to `@route+id`, it switches to `@route^id`. Sealed `- .` opens Move. After body text + space/tab, `.` → `@` for route completion, or `&` first once the item is routed (falls back to `@` only where `&` cannot open). Undo restores `.` | The same rewrite and picker behavior | Native text-field behavior | Native text-field behavior |
| .. | Fast `..`/`;;` (350 ms) types one literal `.`/`;`. Space/Escape restores on an empty route list/picker; item-start `.bashrc`/`.5` stay literal | The same escape and restore behavior | Native text-field behavior | Native text-field behavior |
| ; | After `@route`, `;` → `:` opens Block ID; lone `;` opens Task Link; sealed `- ;` opens Move. After text/marker + space/tab, `;` → `*` where Bob opens Blocks unless `:` applies. Undo restores `;` | The same rewrite and picker behavior | Native text-field behavior | Native text-field behavior |
| - | Literal after a space; Bob maps it to `~` in past segment `x=2-` | The same past-segment rewrite | Native text-field behavior | Native text-field behavior |
| x / s | In close slots, `x`/`s` become `!`/`*` (sized too: `2xx`→`2x!`, `12xs`→`12x*`, `--1 2xx`→`--1 2x!`, `^r:id=2xs`→`^r:id=2x*`); `Plan 2xx`, `x made 2xx`, and `2Xx` stay literal prose. Time goes before `x`, task numbers after it; see [Closing at a size](https://bobs-org.github.io/capture/#closing-at-a-size) | Same | Native text-field behavior | Native text-field behavior |
| = | After space/tab, `=` → `~` opens Links To; after bare `~`/`~~` or a relation token, flips direction. Fast `==` (350 ms) types one `=` | In a relation picker, flips Links To ↔ Linked From; fast `==` undoes into the filter | Native text-field behavior | Native text-field behavior |
| \\ or / | Blank-draft `\` → `/` opens Go To. Else `/` → `#` and `\` → `%` when eligible (`Buy milk \` → `Buy milk %`); `\` stays literal at line start, glued to a word, or after another `\`. `/` stays literal in `=/`, `[[folder/`, section and Pomodoro names. Same-key double-tap types one literal, closes the menu; Undo restores it | The same rewrite and menu behavior | Native text-field behavior | Native text-field behavior |
| Tab | Expand an immediately preceding `--` to `—`; otherwise indent the current column-zero continuation bullet to two spaces (normal focus traversal if neither applies) | Accept the selected completion; with no selected row, take the first | In link mode cycle suggestions; in the `@route+` prompt consume the key | Consume the key; do not expand, indent, or capture |
| Shift-Tab | Outdent the current two-space continuation bullet to column zero (normal reverse focus traversal otherwise) | Same outdent, then close completion | In link mode cycle suggestions backward; in the `@route+` prompt consume the key | Consume the key; do not outdent or capture |
| Down / Ctrl-N | (normal focus traversal) | Select the next completion; with no selected row, select the first | Consume the key; do not move completion selection | Consume the key; do not move completion selection |
| Up / Ctrl-P | (normal focus traversal) | Select the previous completion; with no selected row, select the last | Consume the key; do not move completion selection | Consume the key; do not move completion selection |
| Ctrl-D | (no editor binding) | Hide or show the selected type in a `task_type` menu, or the selected history row in a `pomodoro_name`/`pomodoro_start_name` menu, via `bob themes hide`/`unhide`. Typed rows never write; the ghost row stays until the draft changes | Native text-field behavior | Native text-field behavior |
| Escape / Ctrl-[ | Close the panel, retaining a nonempty draft without confirmation | Close completion | Cancel back to the task list | Cancel back to the Pomodoro list |
| Ctrl-Tab / Ctrl-Shift-Tab | Switch to Bob Refs, retaining the draft and caret | Same switch, closing completion | Same switch; the prompt closes and the draft is retained | Same switch; the prompt closes and the draft is retained |
| Control-S | Open the canceled-draft stash picker | Open the canceled-draft stash picker | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| Control-T | Open the saved-template shelf | Open the shelf and close completion | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| Command-\ | Open today's daily note in Obsidian with the caret on the running Pomodoro (when none is running: the first open entry, else the last completed, else the note's first line), hide the panel, and retain a nonempty draft. See [Going to a task from any app](#going-to-a-task-from-any-app) | Same, and close completion | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| \ | From a blank draft, replace it with `/` to open Go To; on a bare `/` draft right after, type a literal `\`; otherwise consume the key (reopening from the chip when visible) | Same as in the editor | Native text-field behavior | Native text-field behavior |
| Command-J | Join the focus calendar event in the default browser when the draft is empty and the band shows a join link; with a nonempty draft the key is unconsumed | Unconsumed (completion stays open) | Native text-field behavior | Native text-field behavior |
| Command-S | Save the current `%t` draft | Save the current `%t` draft | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| Control-C | Stash a nonempty draft, then clear and close. A Go To (`/`) draft is discarded instead of stashed, and nothing is retained when stashing is off (capacity 0) | Same as in the editor | Same as in the editor | Same as in the editor |
| Command-1…5 | Focus that similar-tasks row and open its strip; pressing the same key again unfocuses it | Close completion, then focus that row | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |

### Record cards

Tab accepts a visible field or value, or requests the first missing field.
At a create route the existing-record list stays visible; Tab still
requests the first missing field, and Return or a click accepts the
selected record. Shift-Tab requests the previous and stays at the first.
Clicking asks Bob for a field. Edit applies Bob's exact text as one
undoable change. Return accepts a selected suggestion or waits for
readiness; otherwise it focuses the first missing field and says
`Needs <field>`. Escape closes suggestions, then the card. Next Escape
behaves normally.

### Notebook note rows

In a notebook `@route+` picker, rows select note bullets rather than tasks.
Return, Tab, and click keep the usual picker behavior; an ID-less note opens
Add block ID and preserves the existing Tab / Shift-Tab suggestion cycling.
Notebook notes have no task status controls.

## Capture picker keys

Picker cards: Return accepts; Escape cancels; Backspace on an empty filter removes its trigger. In Go To, `\` is consumed except a second `\` right after opening (types a literal). Command-X switches open/completed tasks only in Go To (`/`); elsewhere it stays native. Relation pickers (`~` / `~~`) flip live on `~` / `=`; Backspace on `~~` flips back; fast `==` undoes the flip into the filter, and a live `=` opener teaches `== types =`. If `=` opens Links To, Space restores `= ` and Escape restores `=` on an empty filter. In the editor, a glued `~` / `=` at a complete token's end flips without a picker; after a label only `~` flips; Control-Return inserts the token and opens its label card. `|` after a relation token opens that card with or without spaces; Return removes an empty-label pipe. The Task Wikilink picker (`((`) inserts `bob`'s link on Return; Command-Return inserts and captures, Control-Return opens it too. The Move picker (`- ^` / `- :`) inserts the ID on Return, the ID plus continuation on Shift-Return. A merge-in source picker (`< +`) accepts comma or Shift-Return to keep picking on Bob's `continuation`. A refused merge-in offers one button per Bob rewrite (`Use >`, `Move before <`, `Add spaces`); buttons apply those rewrites undoably, while Return does not. See [Pickers](pickers.md) and [Relationship pickers](relationship-pickers.md).

## Move choices

A first-level `- ^^` in a sealed project-note draft opens the Move card on
Return, before any write and before successor choices or inbox routing.

| Key | Action |
| --- | --- |
| `^` / `:` | Set Move / Move & link, then advance to the next enabled row |
| Space | Toggle Leave ↔ Move; a linked mark returns to Leave |
| Up/Down, Control-P/Control-N | Move the highlight without selecting |
| Command-A | Mark visible Leave rows as Move; repeat to clear those marks |
| Other typing / Backspace | Filter in parent order; marks outside the filter stay |
| Return | Apply marks; with no marks, show a hint and stay |
| Shift-Return | Explicitly create without moving any chosen tasks |
| Control-Return | Apply marks, capture, and open Bob's reported notes |
| Escape | Return to the unchanged draft, keeping marks for this parent |

Space types into a nonempty filter. `^` and `:` always set a row's state.
A named project requiring a link blocks Return and Shift-Return until a `:`
pick is made (or the name is removed). Escape from a following successor
card returns to the Move card with its marks. See [Move card](task-pickers.md#move-card).

## Successor choices

Return opens the choice card before writing. Space marks, Command-A preserves Done/Cancel, Control-X stages Done, Control-Shift-X opens the Cancel reason, Shift-Return keeps verdicts, and two Esc presses discard them. Command-X stays Cut. Full behavior is in [Capture previews](capture-previews.md).

## Inbox routing

When a preview reports changing inbox tasks, Return
opens the route card after any successor choice. Up/Down or Control-N/Control-P
moves the destination highlight. Return moves the current task, Control-Return
moves it and opens the capture notes, and Shift-Return keeps it in its inbox.
Escape goes back one task, then to the successor card when one preceded
the route card, or to the unchanged draft. Control-T and Command-\ are consumed
while the route card is open so the shelf and Pomodoro action cannot
take over its modal keys. Full behavior is in [Capture previews](capture-previews.md).

## Similar tasks keys

While a similar-tasks row is focused, the strip owns its keys; any other
key unfocuses first, then passes through unchanged (including `⌘Z` and `⌘↩`).
The footer names the default so Return stays meaningful.

| Key while a row is focused | Action |
| --- | --- |
| `⌘1`…`⌘5` | Focus that row; the same key again unfocuses it |
| Left / Right | Choose the previous or next action in the strip |
| Up / Down | Move between rows (`↓` on the last visible row reveals the next hidden match) |
| Return | Apply the chosen action |
| `~` `+` `&` `*` `/` | Apply that action directly |
| `⌫` | Discard mine, when Bob offers it |
| Escape / Ctrl-[ | Unfocus and return to typing |

## Relation card keys

The relation card keeps search text separate from the highlighted label.
Filtering is local after Bob returns the catalog.

| Key | Action |
| --- | --- |
| Ctrl-N / Down | Select the next visible label; from the last label, return to the field |
| Ctrl-P / Up | Select the previous visible label; from the first label, return to the field |
| Tab | Insert the selected label, or the first visible match when none is selected |
| Shift-Tab | Consume the key |
| Return | Insert the selected label; otherwise insert the authored label Bob validated. With an empty field, insert a plain link and drop the pipe |
| Ctrl-D | Hide what Return would insert (the row stays as a ghost; Ctrl-D on the ghost undoes). With no selection, toggle one-off. Key auto-repeat is ignored |
| `\|` | Turn one-off on; the pipe never enters the field |
| Backspace on an empty field | Turn one-off off |
| Ctrl-H | Show or hide the Hidden section; the query and selection are kept |
| Ctrl-R | Rename the selected label (or the typed label when it names an existing one) everywhere |
| `~` / `=` | Flip direction in choose mode, re-asking Bob and keeping query and selection; repeat is consumed |
| Fast `==` | Undo a `=` flip into `=` (350 ms) |
| Click a row | Accept it; the eye icon on a hovered or selected row hides or unhides it |
| Click ◌ N hidden | Toggle the Hidden section |
| Escape / Ctrl-[ | Leave rename first; else restore the picker and its draft after Control-Return (flipped if the card flipped), or keep the token from `\|` |

With one-off on, Return inserts the `||` form: capturing hides the label from
suggestions everywhere. On a visible label the card warns in amber
before capturing; on a hidden label it notes the label stays hidden.
Ghost-hide rows read `hidden everywhere · ⌃D undo`; ghost-unhide rows read
`visible again · ⌃D undo`. Hidden labels stay usable and hidden: accepting
one inserts the `|` form with a `(stays hidden)` footer. An older Bob shows no
Hidden pill; Ctrl-D and Ctrl-H give the update hint, and `||` is never
downgraded to `|`.

Ctrl-R opens rename mode with the old name prefilled: the card shows a live
dry-run preview (`N links in M notes · mirrors · 1 commit`), Return renames
everywhere in one commit, and Escape returns to the picker keeping the query and
selection. Merging into an existing label asks twice (`↩ again to merge`).
After a rename the card selects the new label and rewrites matching relations
in the open draft. An older Bob shows `Update bob to rename relation labels`.

## Focus

Every capture action is reachable from the keyboard alone; the hotkey, editor, completion
list, Stash/Capture/Preview/Discard buttons, Open chip, and stash picker never need a pointer.
Opening the **Add block ID**, **Name Pomodoro**, or **Relation** prompt moves keyboard
focus into its field; the first responder is owned directly by AppKit
rather than SwiftUI focus, and a keystroke arriving while nothing holds focus re-claims
the field.

## Canceled-draft stash keys

| Key while stash is open | Behavior |
| --- | --- |
| 1...9, 0, A...C, -, E...Z | Restore that row immediately |
| Shift-D | Delete all retained canceled drafts |
| Return | Restore the selected row |
| Down / Ctrl-N | Select the next row, wrapping at the end |
| Up / Ctrl-P | Select the previous row, wrapping at the top |
| Escape / Ctrl-[ | Close only the stash picker |
| Control-S | Close the stash picker |
| Control-T | Close the stash and open the saved-template shelf |
| Command-\ | Consume the key; finish or cancel the stash first |

The 36-entry bound exists so every retained row has a unique one-key
accelerator while reserving `D` for Delete All: `1` through `9`, then `0`, then `A`
through `C`, `-`, and `E` through `Z`.

## Saved-template shelf keys

| Key while the shelf is open | Behavior |
| --- | --- |
| `1–9 0 A–C - E–Z` | Use that visible template |
| Return | Use the selected template |
| Down / Ctrl-N, Up / Ctrl-P | Move the selection, wrapping at either end |
| Backspace twice | Arm, then delete the selected template |
| Control-S | Close the shelf and open the stash |
| Control-T | Close the shelf |
| Command-\ | Consume the key; finish or cancel the shelf first |
| Escape / Ctrl-[ | Disarm deletion, or close the shelf |

Control-T replaces AppKit's transpose-characters shortcut in the capture editor; in
pickers, prompts, and successor choices it is consumed so it never edits or
transposes text.

## Opening today's Pomodoro (Command-\)

`Command-\` is both the global Capture alias and the in-panel key. From another app,
the first press opens (or focuses) Capture, and a press while Capture is focused opens
today's Pomodoro. So `Command-\` `Command-\` from anywhere lands on today's Pomodoro.
With Settings › Hotkey › **Also open Capture with Command-\\** off, `Command-\` works
only inside the panel, and other apps receive it. Control plus backslash is no longer
bound in Capture. Each press runs a fresh
`bob capture-pomodoros --format json --all` through the pomodoros lane; it does
not use the idle-agenda cache. The app never reads the daily note.

Landing rule, from the decoded response:

1. Missing, empty, or relative `day_file`: status
   `bob sent no daily-note path — update bob`; the panel stays open.
2. The entry with `is_current`: that line, with its `ref` when valid.
3. Else the first `open` entry in document order.
4. Else the last `completed` entry.
5. Else line 1 of the daily note, with no `ref`.

The chosen destination is dispatched as `obsidian://bob-goto-task` with
`path`, `line`, and `ref` when the entry's ref is valid. A missing or invalid
ref builds a line-only URL. Nothing in the vault is written. On success the
panel hides and a nonempty draft is retained exactly like Escape: it is never
stashed, discarded, or captured. On a failed open, status is
`Couldn't open Obsidian` and the panel stays. A failed fetch is
`Couldn't read today's Pomodoros`. A press while a capture is submitting is
`Wait for the capture to finish`. A press while Bob is unresolved is
`Bob is not resolved`. A second press while a fetch or open is already in
flight does nothing. If the panel is hidden before the result lands, the
result is dropped. While the stash, saved-template shelf, Add block ID or
Name Pomodoro prompt, successor-choice card, or a picker is open, Command-\
is consumed so you finish or cancel that surface first.

## Going to a task from any app (Command-\ then \) {#going-to-a-task-from-any-app}

`Command-\` then `\` searches tasks from any macOS app. The first press opens
or focuses Capture with the editor focused (release Command); with
Settings › Hotkey › **Also open Capture with Command-\\** on, `\` typed into
the blank draft turns into `/` and opens the Go To picker. This depends on the
alias setting: with it off, `\` still opens Go To inside the panel but the
global chord only works there.

Contrast with `Command-\` `Command-\`, which opens today's Pomodoro. The
retained-draft caveat applies: `\` starts Go To only from a blank draft or a
bare `/` draft, so stash (Control-C) or clear a retained capture first.
Typing `\` `\` right away types one literal `\`, so a draft can still start
with a capture escape such as `\#fix`. After `#` or `%`, double-tap leaves
one literal.

## Editing the draft

Ctrl-J starts the next canonical `- ` row from anywhere in the draft, copying exactly the
current authored row's supported indentation (zero or two ASCII spaces). With a
collapsed caret at column zero, inside leading whitespace, on either side of the hyphen,
after the `- ` prefix, or anywhere through the first body character of a populated `- `
row, Ctrl-J replaces that row's leading whitespace and `- ` prefix with one line
terminator while preserving the body. For example, `Parent\n|- child` and
`Parent\n- |child` both become `Parent\n\n|child`. Only a caret inside or after the body
keeps the normal new-row insertion behavior. On a line that
contains only optional whitespace plus one `-`, `*`, or `+` marker, Ctrl-J replaces the
placeholder with exactly one blank item separator and puts the caret at the beginning of
the following line, reusing an existing line terminator when one is already there.
In a template draft, as reported by bob's parse, Ctrl-J inserts a plain newline
everywhere in the draft with no indentation and no `-`.
macOS smart-dash substitution is disabled in the draft editor so `--3` and `-2`
remain ASCII hyphens; smart quotes are unchanged. Plain Tab first checks
for a local editor snippet: with a collapsed caret immediately after `--`, it
replaces those two ASCII hyphens with a single em dash `—` and leaves the caret
right after it, everywhere else in the editor including inside prose. To submit
a one-unit earlier shift, type `--` and press Return without pressing Tab first.
Only when no snippet matches does Tab fall through to bullet indentation. To
author a nested row,
press Ctrl-J from an existing nested row, or press Ctrl-J for a fresh top-level
placeholder and then Tab before or after typing its body to indent it under the preceding
first-level bullet. Shift-Tab reverses that, returning a nested bullet to column zero.
Tab/Shift-Tab only move a continuation bullet between Bob's two supported source
prefixes, exactly two ASCII spaces, so pasted or hand-authored drafts must still use that
exact two-space indent; they stop at that ceiling and floor and leave every other line
untouched. Ctrl-U deletes from the caret to the beginning of the current physical line,
and when the caret is already at that start -- where there is nothing left to delete --
it removes the previous line entirely, so repeated presses walk up the draft line by line
and stop on the first line.
Ctrl-G is a one-key editor leader. After Control-G, the next key is consumed: `u`
toggles the current physical line's case (uppercase unless the span is already all
uppercase, then lowercase), Escape, Ctrl-[, or a second Control-G cancels silently,
and any other key beeps and is swallowed so it cannot also act. Holding Control-G
stays armed. A click, hiding the panel, or losing key focus drops the leader, and
the footer reads `⌃G · U toggle line case · esc cancel` while it waits. A selection
that spans lines uses one direction for every touched physical line, without changing
line terminators. The toggle does not know capture syntax (`x1` becomes `X1`); Bob's
live parse re-reads the result.
Backspace on an empty `- ` row removes it in one action instead of requiring two ordinary
backspaces. All five shortcuts act on the native text view directly, so undo, IME
composition, and accessibility behave exactly as they do for any other edit, and Bob's
live parse/preview remains the sole authority for whether the resulting hierarchy is
contextually valid. Ctrl-A and Ctrl-E move the caret to the beginning and end of the
current physical line, and when the caret is already on that edge they step to the
beginning of the previous line or the end of the next one, so repeated presses walk the
draft line by line. They stop at the first and last line rather than wrapping around.

Ctrl-Shift-J and Ctrl-Shift-K move the caret to the next and previous physical line,
keeping the column it started from: passing through a shorter line clamps the caret
to that line's end, and the next press in the same direction restores the original
column on the first line long enough to hold it. Other input, clicks, or edits reset
that remembered column. They stop at the first and last lines without wrapping. Exact Ctrl-K
is again left to AppKit's native delete-to-end-of-paragraph binding, while
Ctrl-Shift-K is the custom upward move and Ctrl-U remains Bob's custom line-deleting
shortcut.

Ctrl-L and Ctrl-H move by WORD (vim `W` / `B`): a WORD is a run of non-blank
characters, so `@foo#bar` is one WORD but four words (`@`, `foo`, `#`, `bar`).
Ctrl-Shift-L and Ctrl-Shift-H move by word (vim `w` / `b`): a word is one
keyword, emoji, or punctuation run. Empty lines are stops; lines holding only
spaces are not. A selection collapses first — forward motions start from its
end and backward motions from its start. The motions stop at the start and end
of the draft rather than wrapping around. They only move the caret, so they never
touch the draft's text, undo history, or an in-flight IME composition. In the
editor, Ctrl-H no longer acts as AppKit's delete-backward; Backspace and Ctrl-U
still delete. Prompts and pickers keep their own Ctrl-H, including the relation
card's Hidden-section toggle.

Command-V intentionally reads only the clipboard's plain-text flavor. Source formatting
is discarded because Bob's capture grammar is plain text, and letting AppKit choose a
rich HTML/RTF flavor forced a synchronous WebKit HTML import that could cost seconds per
paste from browser content. When the caret is at the end of an otherwise empty `- `,
`* `, or `+ ` row and the clipboard begins with a Markdown `-`, `*`, or `+` bullet with
a body, Command-V treats that row as the first pasted bullet: the row's marker is kept,
the clipboard's first marker is consumed, and the remaining pasted lines are rebased to
the row's column-zero or two-space indentation.

```text
Plan rollout
-
```

Pasting:

```text
- Confirm owner
- Attach checklist
```

Produces:

```text
Plan rollout
- Confirm owner
- Attach checklist
```

Every other clipboard shape, selection, caret position, and unsupported indentation
still follows ordinary plain-text insertion.
