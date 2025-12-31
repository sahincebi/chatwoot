# 0004 - Centralize Support Tickets in Support HQ Account

## Status
Accepted

## Context
Support requests created from the dashboard were opening conversations inside the requester account, which caused tickets to appear in normal Conversations/My Inbox and channel lists. We need a centralized, super-admin managed support flow that does not mix with account conversations.

## Decision
All support requests are routed to a single Support HQ account/inbox configured via installation configs. The support form posts to a dedicated `support_requests` endpoint, which creates the conversation inside the HQ account and stores requester metadata in conversation additional attributes. Support inboxes are marked with `is_support` and excluded from default inbox and conversation listings.

## Consequences
- Support tickets are visible only in the Super Admin support area.
- Customer accounts no longer see support tickets in conversation lists.
- Support HQ account/inbox must be provisioned and configured via installation configs.
