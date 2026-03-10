# Changelog (Unreleased)

Record image-affecting changes to `manager/`, `worker/`, `openclaw-base/` here before the next release.

---

- feat(openclaw-base): switch from OpenClaw fork (johnlanni/openclaw@df5225e) to upstream openclaw/openclaw v2026.3.8; version-independent native addon verification; parameterized OPENCLAW_VERSION build arg
- feat(manager): add `messages.groupChat.mentionPatterns: ["@manager:"]` to Manager config for regex-based mention detection (replaces fork's source-level mention bypass)
- feat(worker): set `requireMention: false` in Worker config (Workers receive all messages from authorized senders, respond only when @mentioned per AGENTS.md instructions)
- docs: update @mention protocol across all AGENTS.md, SKILL.md, TOOLS.md, and FAQ to reflect new mention model
