---
title: "Mac Capture keyboard"
description: "Every Bob Mac Capture key binding: editor, completion, prompts, stash, shelf, and today's Pomodoro."
---

Every capture action is reachable from the keyboard alone. Successor choice cards are described in [Capture previews](capture-previews.md); stash behavior in [Capture panel](capture-panel.md); template shelf behavior in [Saved templates](saved-templates.md). Global chord conflicts are in [Resolve a Mac Capture hotkey conflict](https://bobs-org.github.io/guides/resolve-mac-capture-hotkey-conflict/).

## Switching panels

In either panel, Ctrl-Tab and Ctrl-Shift-Tab switch to the other panel. From Capture the draft and caret are retained; from Bob Refs the remembered query, scope, filters, selection, and inspector place are restored. The switch works even while a picker, prompt, stash, shelf, or Refs card is open: that surface closes exactly as on a hotkey switch, with the draft and view kept. While IME-composing, the key belongs to the text system; a held key repeats without ping-ponging.

## Bob Refs shortcuts

These rows act in the Bob Refs panel; [Bob Refs](refs.md) and [Bob Refs inspector](refs-inspector.md) expand them. Global Control-Shift-Command-O and `Command-/` toggle the panel from any app; see [Opening Bob Refs](refs.md#opening-bob-refs).

| Key | Action |
| --- | --- |
| Command-S (in Highlights) | Scan after the library PDF saves when the setting is on; the key reaches Highlights unchanged |
| Option-N | Mark the selected Ready or Next reference Seen, or New again; the row stays put until the next re-rank; other rows beep |
| Command-T | Toggle the Tabs filter; the query and kind scope stay in place |
| Command-T (in Highlights) | While Highlights is frontmost and Bob Refs is hidden, open Bob Refs in Tabs from fresh defaults with the focused PDF selected; configurable to Shift-Command-O, Command-E, or Off |
| Command-Y | Open the Copy card for the selected row |
| Command-Y (in Highlights) | While Highlights is frontmost and Bob Refs is hidden, open the Copy card on the focused PDF; configurable to Off. Keys typed before the PDF is known are replayed on the card |
| Command-B | Open the Copy card for the selected row with the code picker pressed |
| Command-L | Open the Copy card for the selected row with the link picker pressed |
| Command-B / Command-L (in Highlights) | Registered only while Highlights or its override app is frontmost; opens the code or link picker on the focused PDF, yields while Bob Refs is visible, and can be set to Off. Keys typed before the PDF is known replay on the card |
| Control-Return | Open the reading task's file in Obsidian (at the task line) |
| Ctrl-X | Close the selected tab in Highlights (Tabs only) |
| Ctrl-D | Scroll the preview down by half its height |
| Ctrl-U | Scroll the preview up by half its height |
| Ctrl-C | Reset the query, filters, selection, revealed pages, and scroll positions |
| Escape / Ctrl-[ | Close cards and banners, then the panel while keeping its view |
| Shift-Command-T | Reopen the most recently closed Highlights tab |
| Ctrl-Tab / Ctrl-Shift-Tab | Switch to Capture, keeping the remembered view |

## Copy card keys

Command-Y, Command-B, or Command-L opens the Copy card for the selected row, or for the focused Highlights PDF when Highlights is frontmost. Command-B starts in the code picker; Command-L starts in the link picker. While the card is open:

| Key | Action |
| --- | --- |
| C | Open the code picker when the reference has saved Markdown and recorded blocks (from Markdown or a web page) |
| L | Open the link picker when the reference has saved Markdown and recorded links (from Markdown or a web page); Option-U copies the Markdown link |
| M | Copy the saved Markdown source; Option-M copies its `~` path |
| 1–9 | Copy that visible note, or that visible code, highlight, or link once a picker is open |
| Shift-1–9 / Shift-Return | In a link picker, open that visible / selected web link in the default browser |
| Return | Copy the selected row, or open the C, H, or L picker when that row is selected |
| Option-Return | Copy the fenced form of the selected code block, or the Markdown form of the selected link |
| A | In a highlight picker copy all highlights; in a link picker copy every distinct URL (Option-A as a Markdown list) |
| Up / Down | Move the selection (and the code or link preview well) |
| Escape / Ctrl-[ | Return to the card from a picker, then to the inspector |

Command-B Return from Highlights copies the code block on the current PDF page.
Command-L Return copies the link on the current PDF page. Without saved Markdown,
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
| Return | Capture, then close the panel | Accept the selected completion | Add the ID and select the task | Name the Pomodoro and select it |
| Control-Return | Capture, open Bob's reported notes on their captured lines, then close the panel | Accept, then capture and open if no picker or prompt follows (template headers only accept) | Same as Return; keep an open intent from a picker | Same as Return; keep an open intent from a picker |
| Command-Return | Same as Control-Return | Same as Control-Return | Consume the key; do not capture | Consume the key; do not capture |
| Shift-Return / Option-Return | Insert a newline | Insert a newline | Add the ID and select the task | Name the Pomodoro and select it |
| Ctrl-J | Insert a new indentation-aware `- ` row; anywhere before a populated dash bullet's body, remove the prefix into a blank separator and keep its body; in a template draft, as reported by bob's parse, insert a plain newline | Same edit, and close completion | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-O | Insert a blank physical line immediately above the current line and move the caret onto it | Same edit, and close completion | Native text-field behavior | Native text-field behavior |
| Ctrl-U | Delete from the caret to the beginning of the current physical line; when the caret is already at that start, delete the previous line instead, stopping on the first line | Same deletion, closing completion | Native text-field behavior | Native text-field behavior |
| Ctrl-A | Move to the beginning of the current physical line; when the caret is already there, move to the beginning of the previous line, stopping on the first line | Same move, leaving completion open and re-anchored at the new caret | Native text-field behavior | Native text-field behavior |
| Ctrl-E | Move to the end of the current physical line; when the caret is already there, move to the end of the next line, stopping on the last line | Same move, leaving completion open and re-anchored at the new caret | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-J | Move the caret to the next physical line, keeping the current column when that line is long enough and clamping to its end when it is not; stops on the last line | Same move, leaving completion open and re-anchored at the new caret | Native text-field behavior | Native text-field behavior |
| Ctrl-Shift-K | Move the caret to the previous physical line, keeping the current column when that line is long enough and clamping to its end when it is not; stops on the first line | Same move, leaving completion open and re-anchored at the new caret | Native text-field behavior | Native text-field behavior |
| Command-V | Insert the clipboard's plain text, discarding source formatting; when an empty bullet row receives a Markdown bullet list, consume the first pasted marker and align the list to that row | Same paste edit, and close completion | Native text-field paste | Native text-field paste |
| @ | After a first line exactly `@@`, ask bob to start a template: `@@@` becomes `@@template:` with the caret on a new line. At the end of any other line, a standalone `@@` plus `@` is erased and `@@template:` becomes the first line, with the caret staying where the token began. Undo restores the literal `@@@`; everywhere else, insert `@` normally | Same rewrite and close completion; the list header shows the hint only on the first line | Native text-field behavior | Native text-field behavior |
| Backspace | Remove an auto-inserted `,<digit>` pair together, else remove an unused `- ` row in one action (native Backspace everywhere else, and for every modified Backspace) | Remove an unused `- ` row in one action | Native text-field Backspace | Native text-field Backspace |
| 1–9 | Right after a task number in a close task list (`x`, `x*`, `x!`, and their `*`/`!`/`~` groups, including `=x` link closes), insert `,` before the digit (`x1` + `2` → `x1,2`) when the running Pomodoro has fewer than 10 numbered Task Links; otherwise the digit types normally | Native text-field behavior | Native text-field behavior | Native text-field behavior |
| + | Insert `+` | While route completion is visible, directly after the route being completed: accept the selected route, keep the `+`, and open task completion; the `@@template:` candidate is excluded | Native text-field behavior | Native text-field behavior |
| Tab | Expand an immediately preceding `--` to `—`; otherwise indent the current column-zero continuation bullet to two spaces (normal focus traversal if neither applies) | Accept the selected completion | In link mode cycle suggestions; in the `@route+` prompt consume the key | Consume the key; do not expand, indent, or capture |
| Shift-Tab | Outdent the current two-space continuation bullet to column zero (normal reverse focus traversal otherwise) | Same outdent, then close completion | In link mode cycle suggestions backward; in the `@route+` prompt consume the key | Consume the key; do not outdent or capture |
| Down / Ctrl-N | (normal focus traversal) | Select the next completion | Consume the key; do not move completion selection | Consume the key; do not move completion selection |
| Up / Ctrl-P | (normal focus traversal) | Select the previous completion | Consume the key; do not move completion selection | Consume the key; do not move completion selection |
| Escape / Ctrl-[ | Close the panel, retaining a nonempty draft without confirmation | Close completion | Cancel back to the task list | Cancel back to the Pomodoro list |
| Ctrl-Tab / Ctrl-Shift-Tab | Switch to Bob Refs, retaining the draft and caret | Same switch, closing completion | Same switch; the prompt closes and the draft is retained | Same switch; the prompt closes and the draft is retained |
| Control-S | Open the canceled-draft stash picker | Open the canceled-draft stash picker | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| Control-T | Open the saved-template shelf | Open the shelf and close completion | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| Command-\ | Open today's daily note in Obsidian with the caret on the running Pomodoro (when none is running: the first open entry, else the last completed, else the note's first line), hide the panel, and retain a nonempty draft | Same, and close completion | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| Command-S | Save the current `@@template:` draft | Save the current `@@template:` draft | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |
| Control-C | Stash a nonempty draft, then clear and close. A Go To (`/`) draft is discarded instead of stashed, and nothing is retained when stashing is off (capacity 0) | Same as in the editor | Same as in the editor | Same as in the editor |
| Command-1…5 | Focus that similar-tasks row and open its strip; pressing the same key again unfocuses it | Close completion, then focus that row | Consume the key; finish or cancel the prompt first | Consume the key; finish or cancel the prompt first |

## Capture picker keys

While a picker card is open, Return accepts the selected row, Escape cancels, and Backspace on an empty filter removes the trigger. Relation pickers (`~` / `~~`) treat `~` anywhere in the filter as a live direction flip and Backspace on `~~` as a flip back. Shift-Return inserts the relation token and opens its label card. In the editor, typing `|` after a relation token opens that card with or without spaces before the pipe; an empty-label Return removes the pipe. Source-specific hints live in [Pickers](pickers.md) and [Relationship pickers](relationship-pickers.md).

## Successor choices

When a preview reports successor offers, Return opens the grouped choice card before anything is written. Space marks the highlighted offer, Command-A marks all, Shift-Return skips with no offers, and Escape returns to the unchanged draft. Full card behavior is in [Capture previews](capture-previews.md).

## Inbox routing

When a matching preview reports inbox tasks whose status will change, Return
opens the route card after any successor choice. Up/Down or Control-N/Control-P
moves the destination highlight. Return moves the current task, Control-Return
moves it and opens the capture notes, and Shift-Return keeps it in its inbox.
Escape goes back one task, then returns to the successor card when one preceded
the route card, or to the unchanged draft. Control-T and Command-\ are consumed
while the route card is open so the template shelf and Pomodoro action cannot
take over its modal keys. Full behavior is in [Capture previews](capture-previews.md).

## Similar tasks keys

While a similar-tasks row is focused, the strip owns its keys and any other
key unfocuses first, then passes through unchanged (including `⌘Z` and `⌘↩`).
The footer names the default so the meaning of Return stays visible.

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

The relation card keeps the search text separate from its highlighted label. Filtering
is local after Bob returns the catalog, so moving through labels never starts another
completion request.

| Key | Action |
| --- | --- |
| Ctrl-N / Down | Select the next visible label; from the last label, return to the field |
| Ctrl-P / Up | Select the previous visible label; from the first label, return to the field |
| Tab | Insert the selected label, or the first visible match when none is selected |
| Shift-Tab | Consume the key |
| Return | Insert the selected label; otherwise insert the authored label Bob validated. With an empty field, insert a plain link and drop the pipe |
| Ctrl-D | Hide what Return would insert (the row stays as a ghost; Ctrl-D on the ghost undoes). With no selection, toggle one-off for the typed label. Key auto-repeat is ignored |
| `\|` | Turn one-off on; the pipe never enters the field |
| Backspace on an empty field | Turn one-off off |
| Ctrl-H | Show or hide the Hidden section; the query and selection are kept |
| Ctrl-R | Rename the selected label (or the typed label when it names an existing one) everywhere |
| Click a row | Accept it; the eye icon on a hovered or selected row hides or unhides it |
| Click ◌ N hidden | Toggle the Hidden section |
| Escape / Ctrl-[ | Leave rename mode first; otherwise return to the relation picker, or to the editor when the card opened from `|` |

With one-off on, Return inserts the `||` form: capturing hides the label from
suggestions everywhere. On an existing visible label the card warns in amber
before capturing; on an already-hidden label it notes the label stays hidden.
Ghost-hide rows read `hidden everywhere · ⌃D undo`; ghost-unhide rows read
`visible again · ⌃D undo`. Hidden labels stay usable and stay hidden: accepting
one inserts the `|` form with a `(stays hidden)` footer. An older Bob shows no
Hidden pill; Ctrl-D and Ctrl-H give the update hint, and `||` is never
downgraded to `|`.

Ctrl-R opens rename mode with the old name prefilled: the card shows a live
dry-run preview (`N links in M notes · mirrors · 1 commit`), Return renames
everywhere in one commit, and Escape returns to the picker with the query and
selection kept. Merging into an existing label asks twice (`↩ again to merge`).
After a rename the card selects the new label and rewrites matching relations
in the open draft. An older Bob shows `Update bob to rename relation labels`.

## Focus

Every capture action is reachable from the keyboard alone; the hotkey, editor, completion
list, Stash/Capture/Preview/Discard buttons, the Open chip, and stash picker never require a pointer.
Opening the **Add block ID**, **Name Pomodoro**, or **Relation** prompt moves keyboard
focus into that prompt's field; the field's first responder is owned directly by AppKit
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

The 36-entry upper bound exists so every retained row always has a unique one-key
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

Control-T replaces AppKit's transpose-characters shortcut in the capture editor. Inside
capture pickers, prompts, and successor choices it is consumed so it never edits or
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
stay literal ASCII hyphens; smart quotes are unchanged. Plain Tab first checks
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
Backspace on an empty `- ` row removes it in one action instead of requiring two ordinary
backspaces. All five shortcuts act on the native text view directly, so undo, IME
composition, and accessibility behave exactly as they do for any other edit, and Bob's
live parse/preview remains the sole authority for whether the resulting hierarchy is
contextually valid. Ctrl-A and Ctrl-E move the caret to the beginning and end of the
current physical line, and when the caret is already on that edge they step to the
beginning of the previous line or the end of the next one, so repeated presses walk the
draft line by line. They stop at the first and last line rather than wrapping around, and
because they only move the caret they never touch the draft's text, undo history, or an
in-flight IME composition.

Ctrl-Shift-J and Ctrl-Shift-K move the caret to the next and previous physical line,
keeping the column it started from: passing through a shorter line clamps the caret
to that line's end, and the next press in the same direction restores the original
column on the first line long enough to hold it. Any other keystroke, click, or edit
resets that remembered column. They stop at the last and first line rather than
wrapping around, and like Ctrl-A and Ctrl-E they only move the caret, so they never
touch the draft's text, undo history, or an in-flight IME composition. Exact Ctrl-K
is again left to AppKit's native delete-to-end-of-paragraph binding, while
Ctrl-Shift-K is the custom upward move and Ctrl-U remains Bob's custom line-deleting
shortcut.

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
