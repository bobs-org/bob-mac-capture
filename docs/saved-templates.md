---
title: "Mac Capture saved templates"
description: "Save, shelve, and reuse capture drafts with the Bob Mac Capture template shelf."
---

The Control-T shelf reuses saved `@@template:` blocks. Shelf keys are in [Keyboard](keyboard.md); template preview rows are in [Capture previews](capture-previews.md); the list/save endpoints are in [Protocol](protocol.md).

## Saved templates

Bob Mac Capture's Control-T shelf reuses saved `@@template:` blocks. Picking a row
inserts bob's draft at the start of the editor as one undoable edit and checks out that
template in app memory. The original remains on disk. While it is checked out, the
Templates count and shelf omit it. Escape, hiding the panel, and a failed capture keep
the checkout. A successful capture moves the used block to the top; if you edited it,
the new block replaces the checked-out one. Command-S saves the current template block
without clearing the draft, and the next successful capture settles that checkout.

Discard releases the checkout and returns the original to the shelf. Removing the
template header and receiving a fresh parse without a template, emptying the editor, or
using Command-Z to undo the insert also releases it. Control-C stashes the full draft
without checkout metadata and reports "Canceled draft stashed · template kept"; restoring
that draft does not check out the template again. Quitting or crashing loses the draft
and its in-memory checkout, while the shelf remains unchanged.

The shelf stores the template block, never the capture rows. It lives at
`${XDG_STATE_HOME:-~/.local/state}/bob-cli/capture/templates.json` with mode `0600`;
`BOB_CAPTURE_TEMPLATES_FILE` can override the file path. The default capacity is 36,
configured with `capture.max_saved_templates`; setting it to 0 turns off automatic and
Command-S saves while leaving existing templates available. Forced `-r`, `-s`, and `-t`
destinations are not saved. Settings shows the count and file path, can reveal the file
in Finder, and has a confirmed **Clear Templates…** action that also removes the
quarantine copy.

An older bob that does not know `capture-templates` hides the shelf and asks you to
update bob. The app only sends `--template-origin` after a successful template-list
request from that same bob executable. This identity check matters because an older
`bob capture` can swallow an unknown option as capture text instead of rejecting it.
If bob changes after the list request, an edited template is saved as a separate entry
and the original stays safe.

Required bob features are `capture-templates list`, `capture-templates save`, and
`capture --template-origin`. The list endpoint supplies the draft, caret, parse spans,
and identity evidence; the app renders those results without parsing capture grammar.
