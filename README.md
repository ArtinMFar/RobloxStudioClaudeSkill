# Roblox Studio Claude Skill

A Claude skill for running **Roblox Studio inside a Claude Code cloud
container** (headless Ubuntu, no GPU), so Claude can build and publish Roblox
games from there.

It runs Studio under Wine on a virtual X display with CPU rendering, and
Claude drives it with screenshots and simulated mouse and keyboard input.

**The whole skill is one file:**
[`.claude/skills/roblox-studio/SKILL.md`](.claude/skills/roblox-studio/SKILL.md).
Its setup scripts are embedded in the file's appendix, and Claude writes them
to disk on first use. So you can upload just `SKILL.md` as a skill.

Claude Code also picks the skill up automatically when this repository is the
working directory. To use it in another project, copy
`.claude/skills/roblox-studio/` into that project's `.claude/skills/` (or into
`~/.claude/skills/`).

## Status

Install (from a clean container), launch, rendering, screenshots, input and
CPU management work. Sign-in needs the human to do Roblox's CAPTCHA/approval
on their own device (see the skill's "Signing in" section). Building and
publishing steps will be verified once a session gets past sign-in.

## Editing the scripts

The scripts live only inside `SKILL.md` (Appendix: script sources). Edit them
there, keep each one inside its fenced code block, and don't use triple
backticks inside a script.
