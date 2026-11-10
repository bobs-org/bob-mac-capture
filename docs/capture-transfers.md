---
title: "Mac Capture task transfers"
description: "Move and merge preview cards, status, notifications, and VoiceOver."
---

## Task transfers (`>`)

A move or merge renders one card per transfer item in draft order. The card follows the
draft: source tasks, a `↓ into` connector, the destination, Bob-authored consequence
sentences, link-repair summary, TODAY badge when Bob returned `plan_budget`, and any
merge hand-off offers. Move uses the route accent and merge uses purple throughout the
card and editor arrow. Source rows show Bob's task title, status transition, locator, and
block-ID change or copied-note count (`title only`, `1 note copied`, `N notes copied`);
the destination shows its status, locator, and created drawer or section. A batch-level
TODAY meter stays above ordinary item cards,
while a single transfer hosts the badge inside its card. Transfer cards stand in for the
generic item header and item-level Pull-In summary. Inbox-route candidates remain above
the card.

After the item cards, landing cards show Bob's exact write previews in Bob's
first-touch order. A merge target wears a purple **Merge target** capsule; each
merged source wears a muted **Merged** capsule and keeps its original notes: the
card shows the cancelled headline and the added `LINKS` line, and the source row
shows the copied-note count (`title only`, `1 note copied`, `N notes copied`).
Moved tasks wear an accent **Moved** capsule and identify their origin
(`from inbox.md:5`); their removed source lines fold into
`⤵ N lines moved to the target`, and **Show all lines** or the row expands the
removed bytes. That removed-run fold stays only for move cards and for older Bob
responses. A merge
into a section shows that section first as `§ Heading · note.md · line N`, with
the heading emphasized and a pink **New**/**Created** capsule when Bob created
it. These landing cards render before the batch's Pomodoro block cards.

The footer status line names the action and resolved destination (`Would merge 2 tasks
into “T” · bob.md › FUTURE WORK`, `Would move 2 tasks into db.md › Tasks`). Return keeps
the **Merge** or **Move** action. Once committed, notifications use `Merged …` or
`Moved …`; each body has one styled source line, Bob's consequence sentences, and the
link-repair line. VoiceOver reads the whole card as one element. If the parsed transfer
verb changes while editing, the panel announces the new verb and Bob-resolved target.
An all-unchanged merge is muted and says `Already merged into “T”` and `Nothing to
write`. Older Bob responses keep working: message rows render as styled fallback text,
and consequence rows are omitted when their additive fields are missing.

While a transfer destination is unfinished, the preview stays neutral and runs Bob's
read-only dry run. When Bob returns `transfer_pending`, the card shows resolved source
tasks, any source-resolution message, and the four destination forms with the active
form highlighted. Older Bob versions keep the preview idle and put Bob's diagnostic in
the muted status line. A complete transfer that Bob refuses shows a `Can't move` or
`Can't merge` card with Bob's message and the muted refusal code; submit-time failures
keep the usual error callout.
