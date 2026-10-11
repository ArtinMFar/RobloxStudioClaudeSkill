# Roblox Studio Claude Skill

A Claude Code skill for running **Roblox Studio inside a Claude Code cloud
container** (headless Ubuntu, no GPU), so Claude can build and publish Roblox
games from there.

It runs Studio under Wine on a virtual X display with CPU rendering, and
Claude drives it with screenshots and simulated mouse and keyboard input.

- Skill: [`.claude/skills/roblox-studio/SKILL.md`](.claude/skills/roblox-studio/SKILL.md)
- Scripts: [`.claude/skills/roblox-studio/scripts/`](.claude/skills/roblox-studio/scripts/)

Claude Code picks the skill up automatically when this repository is the
working directory. To use it in another project, copy
`.claude/skills/roblox-studio/` into that project's `.claude/skills/` (or into
`~/.claude/skills/`).

## Quick start

```bash
S=.claude/skills/roblox-studio/scripts
$S/install.sh          # Wine + Studio (~3-5 min, once per container)
$S/rs.sh start         # launch Studio on DISPLAY=:99
$S/rs.sh shot "" 50    # screenshot (half size) to look at
$S/rs.sh help          # all commands
```

## Status

Install, launch, rendering, screenshots, input and CPU management work.
Sign-in needs the human to do Roblox's CAPTCHA/approval on their own device
(see the skill's "Signing in" section). Building and publishing steps will be
verified once a session gets past sign-in.
