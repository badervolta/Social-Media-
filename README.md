# Volta Social Media Command Centre

One place for Volta's communications lead to monitor and prioritize LinkedIn, Facebook and Instagram activity, with a daily 1:00 p.m. digest.

> **Status: prototype.** All people, organizations and messages are fictional sample data. Nothing is connected to any social account. Nothing is sent, posted, hidden or deleted. Classification uses simple keyword rules, not AI.

## What's in it

- **Unified inbox**: 24 sample interactions across the three platforms, with summary tiles, filters (platform, priority, type, status), search and sorting.
- **Classification**: each item is Urgent, Needs response, Informational or Reviewed, with the rule that matched and a short reason.
- **Review workflow**: Mark reviewed, Needs follow-up, Reopen, plus an activity history per item.
- **Suggested replies**: editable Volta-voice drafts (Friendly or Brief). Facts that must be checked appear in `[brackets]` and block approval. Approving never posts.
- **Moderation queue**: possible abusive, spam or personal-information comments, blurred until revealed. A person decides: keep, hide manually, or escalate.
- **1:00 p.m. digest**: an email-style summary rebuilt on demand from current data, with copy-as-text.

State is saved in the browser's local storage only. "Reset demo" restores the sample data.

## Run locally

It's a single static file with no build step. Open `index.html` in a browser, or serve the folder:

```bash
npx serve .
```

## Deploy

Import this repository in Vercel as a static site. No framework, build command or output directory is needed. Vercel serves `index.html` from the root.

## Roadmap

1. Host on Vercel.
2. Team sign-in for a small allow-list of Volta staff.
3. Read-only connection to Volta's Facebook Page and Instagram business account (Meta Graph API), then LinkedIn (Community Management API, requires approval).
4. Store interactions in a database, send the real 1:00 p.m. digest on a schedule.
5. Keep "approve, then a person posts" for replies and moderation until the team trusts it.

**Never commit API keys, tokens or passwords to this repository.** Use environment variables in Vercel.
