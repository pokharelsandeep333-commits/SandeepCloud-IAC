# AGENTS.md

All instructions for this folder live in **[CLAUDE.md](CLAUDE.md)**. Read it in full before doing anything here. It applies to every agent (Codex, Gemini, Antigravity, Cursor and others), not only Claude.

Short version, so nothing is missed if you stop here:
- Project context lives in the vault: `../Obsidian Vault/LLM-Wiki/Raw/Files/SandeepCloud IaC/`. Read `00 IaC - Project Hub.md` and `05 IaC - Task Board.md` first.
- AI agents are **read-only in AWS**. Never run `terraform apply`, `destroy`, `import` or state commands, and never call AWS write APIs. Sandeep applies.
- No secrets in code, tfvars, outputs or state. Never touch the SRI AWS account.

Keep this file a pointer. Put new rules in CLAUDE.md so the two never drift apart.
