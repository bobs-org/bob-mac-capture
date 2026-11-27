---
title: "Snooze wake notice protocol"
description: "The receipt, Darwin notification, and notifier claim that route Bob snooze wakes to Mac Capture."
---

Mac Capture handles Bob's snooze wake notices only when `bob snooze -f json` advertises `wake_notice_version: 1`. The same response supplies the live eligible rows, Bob's day and vault identity, and the Today link budget. The HUD's **+15m** action writes through `bob snooze add <route:block-id> +15m -f json`; Bob remains the task and vault authority.

After a wake, Bob writes `last-wake.json` in its snooze state directory and posts the Darwin notification `org.bobs.bob.snooze.woken`. The file holds the latest receipt only; it is not a replay queue. The notification is a prompt to read the receipt, not the receipt itself. Mac Capture also reads once at launch to recover a missed ping.

When its observer is registered, the HUD is attached, and Bob supports the protocol, Mac Capture publishes the versioned `notifier.json` claim beside the receipt. Bob's `auto` channel uses `mac_capture` while that claim is live and falls back to desktop notification otherwise. Explicit `desktop` uses the desktop path, and `off` disables notice delivery. Older Bob has no compatible capability, so Mac Capture publishes no claim and Bob keeps the desktop fallback.

Wake records in Notification Center are passive, silent, and keyed by wake ID. They follow the beacon's clearing lifecycle, survive an app restart only while the persisted beacon is active, and never cause a consumed wake to replay. Settings shows metadata-only wake status under **Snoozed Tasks**; see [Settings](settings.md#snoozed-tasks) and [Diagnostics](diagnostics.md).
