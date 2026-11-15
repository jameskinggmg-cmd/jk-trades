# JK TRADES — Early Access Beta

JK TRADES is a UK trades marketplace being opened for a limited early-access beta.

## Beta status
This is a test release. Some features may be incomplete or behave unexpectedly. Do not rely on JK TRADES for urgent or emergency work. Report problems before relying on a workflow for important decisions.

## Current scope
- Customer and tradesperson accounts
- Job posting and open-work browsing
- Quotes and customer/tradesperson conversations
- Job photo uploads and private photo galleries
- Installable PWA foundation for supported mobile browsers

## Known limitations
- Full end-to-end testing with separate customer and approved-tradesperson accounts has not been completed.
- Supabase leaked-password screening is not enabled; registration enforces a 12-character minimum and recommends a unique password.
- Supabase security advisor warnings for authenticated SECURITY DEFINER RPCs remain documented; the functions were manually inspected for authentication and ownership checks.
- Messaging does not currently use realtime subscriptions; users may need to refresh or reopen the page to see new messages.
- Reviews remain disabled until the job-completion lifecycle is confirmed.
- PWA installation and offline behavior have not been verified on real devices.

## Security and privacy
The database uses row-level security and private job-photo storage. Never share passwords or verification codes. Use a unique password. Do not upload sensitive personal or financial documents as job photos.

## Release checks
GitHub Actions currently validates the PWA manifest and JavaScript syntax. This is not a substitute for real-browser, mobile, or account-to-account testing.
