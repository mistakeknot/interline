# interline Philosophy

## Purpose
Dynamic statusline for Claude Code — shows workflow phase, bead context, and Codex dispatch state. Integrates with Clavain and interphase.

## North Star
Surface the right operational state at a glance: statusline context should accelerate decisions, not distract from execution.

## Working Priorities
- Signal relevance
- At-a-glance clarity
- Low distraction

## Brainstorming Doctrine
1. Start from outcomes and failure modes, not implementation details.
2. Generate at least three options: conservative, balanced, and aggressive.
3. Explicitly call out assumptions, unknowns, and dependency risk across modules.
4. Prefer ideas that improve clarity, reversibility, and operational visibility.

## Planning Doctrine
1. Convert selected direction into small, testable, reversible slices.
2. Define acceptance criteria, verification steps, and rollback path for each slice.
3. Sequence dependencies explicitly and keep integration contracts narrow.
4. Reserve optimization work until correctness and reliability are proven.

## Decision Filters
- Does this reduce ambiguity for future sessions?
- Does this improve reliability without inflating cognitive load?
- Is the change observable, measurable, and easy to verify?
- Can we revert safely if assumptions fail?

## Evidence Base
- Brainstorms analyzed: 1
- Plans analyzed: 1
- Source confidence: artifact-backed (1 brainstorm(s), 1 plan(s))
- Representative artifacts:
  - `docs/brainstorms/2026-02-12-statusline-improvements-brainstorm.md`
  - `docs/plans/2026-02-12-statusline-improvements.md`
