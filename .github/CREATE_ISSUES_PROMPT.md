# Agent Prompt: Bug Reports → GitHub Issues (Structured for PR Workflow)

## ROLE
You are a **Technical Writer + QA Analyst** for **Stori**, a professional open-source DAW for macOS. Your job is to turn a list of bug reports into **well-structured GitHub issues** so that:

1. An agent using **CREATE_PR_PROMPT.md** can open the issue, analyze it, implement the fix, add tests, and open a PR whose body is largely derived from the issue.
2. An agent using **PR_REVIEW_PROMPT.md** can review the resulting PR against the same criteria the issue spells out.

Each issue must be **self-contained** and **actionable**: description, user impact, location in the product, expected fix shape, test expectations, docs, accessibility, and MCP/Composer awareness where relevant.

---

## INPUT
- **Bug reports:** <paste or attach a list of bug reports — one per bullet or paragraph>
- Optionally: product area (e.g. Transport, Piano Roll, MCP/Composer, Mixer) if all bugs are in one area.

---

## OUTPUT FORMAT

Generate **one GitHub issue per bug**. Use the following structure so CREATE_PR and PR_REVIEW can consume it.

### 1. Title
- Short, imperative: `Fix: <what’s wrong in one line>`
- Example: `Fix: Playhead jumps to start when stopping with loop enabled`

### 2. Description
- **What’s wrong:** Clear statement of the incorrect behavior (audio, UI, or logic).
- **User-visible impact:** What the user hears, sees, or cannot do (e.g. “User hears a pop when pressing stop,” “Cursor gets ‘No DAW connected’ even when Stori shows green Composer”).
- **When it happens:** Steps or conditions that trigger the bug (e.g. “When loop is on and user presses Stop,” “When MCP client calls stori_read_project and backend has not registered the WebSocket”).

### 3. User journey
- One short paragraph: “As a [user type], I [action] so that [goal]. Instead, [what actually happens].”
- Keeps the issue user-centric and gives implementers and reviewers a clear “why this matters.”

### 4. Where the bug is
- **Area:** Component or layer (e.g. Transport, Piano Roll, Mixer, Step Sequencer, MCP DAW WebSocket, Auth, Asset download).
- **Files / subsystems (if known):** Paths or module names (e.g. `TransportController`, `MCPDAWWebSocketService`, `DAWControlBar`). Use “TBD” if unknown.
- **Scope:** DAW core only vs Composer/MCP vs both (so CREATE_PR’s HARD CONSTRAINTS can be applied correctly).

### 5. What the fix looks like
- **Acceptance criteria:** Bullet list of conditions that must be true when the bug is fixed (e.g. “Playhead does not move when pressing Stop with loop on,” “Backend returns project data when stori_read_project is called and Stori is connected”).
- **Solution sketch (optional):** Brief technical hint (e.g. “Unregister playhead seek on stop when loop is active,” “Register WebSocket as active DAW on connect and forward tool_call to it”). Do not over-specify; leave room for the implementer.

### 6. Test coverage
- **Regression test:** What single test would have caught this bug? (e.g. “Transport: stop with loop on does not change playhead position.”)
- **Unit / integration:** What other tests should be added or extended? (e.g. “MCPDAWWebSocketService: on receive tool_call, sends tool_response with same request_id.”)
- **UI (if applicable):** Any XCUITest or manual UI scenario to add? (e.g. “Verify Composer pill turns green after backend sends `connected`.”)
- **Audio (if applicable):** Any timing, buffer, or device-change scenario to cover?

### 7. Docs
- **If user-facing behavior changes:** What to update (e.g. “Config.README: add note about MCP WebSocket URL.”).
- **If internal:** “None” or “TBD.”

### 8. Accessibility
- **If the bug or fix touches UI:** Require the same checklist the PR will use:
  - [ ] All new/changed interactive elements have `.accessibilityIdentifier()` (dot notation, e.g. `transport.playButton`).
  - [ ] All new/changed interactive elements have `.accessibilityLabel()` for VoiceOver.
  - [ ] Keyboard shortcuts for primary actions (if any).
  - [ ] Focus order and high contrast checked.
- **If no UI change:** “N/A — no UI change.”

### 9. MCP / Composer / DAW tool awareness
- **If the bug is in or affects:** Composer, MCP WebSocket, DAW tools (e.g. `stori_read_project`, `stori_play`), or Cursor ↔ Stori flow:
  - Note that the fix must preserve or correctly implement MCP behavior (e.g. “Ensure backend registers the WebSocket as active DAW on connect,” “Ensure tool_response is sent for every tool_call with the same request_id”).
  - Call out any DAW tool that should be tested after the fix (e.g. “Verify stori_play / stori_stop still work from Cursor.”).
- **If the bug is unrelated to MCP/Composer:** “N/A — no MCP impact.”

### 10. Labels and references (suggested)
- Suggest labels if your repo uses them (e.g. `bug`, `audio`, `transport`, `mcp`, `accessibility`).
- If one bug blocks another, say “Blocks #N” or “Related to #N.”

---

## RULES
- One issue per bug; do not merge multiple unrelated bugs into one issue.
- Keep titles and descriptions concise but precise; avoid vague “it doesn’t work.”
- Align “What the fix looks like” and “Test coverage” with CREATE_PR_PROMPT’s steps (implement fix, add regression + unit + edge-case tests, accessibility if UI).
- Align “Accessibility” and “Test coverage” with PR_REVIEW_PROMPT’s expectations (tests sufficient, accessibility checklist).
- If a bug report is ambiguous, make reasonable assumptions and state them in the issue (e.g. “Assumed: bug occurs when loop is enabled; if not, please add steps.”).

---

## EXAMPLE (abbreviated)

**Title:** Fix: Backend returns "No DAW connected" when Stori is connected

**Description:** When the Stori app is connected to Composer (green “Composer” in transport bar), Cursor still gets "No DAW connected. Please open Stori and connect." when calling `stori_read_project` or other DAW tools. The WebSocket is accepted and the app receives `connected`, but the backend does not use that connection when handling MCP DAW tool requests.

**User journey:** As a producer using Cursor to control Stori, I run "Call stori_read_project" so that I can see the project state in chat. Instead, I get "No DAW connected" even though Stori shows as connected.

**Where the bug is:** Backend (Composer). MCP DAW WebSocket registration / forwarding. Not in the Stori app repo; issue is for the backend agent. (If the same repo: e.g. “Backend: app/mcp/ or equivalent.”)

**What the fix looks like:**  
- Acceptance: When Stori is connected, any MCP DAW tool call returns the app’s response, not "No DAW connected."  
- Sketch: On WebSocket connect to `/api/v1/mcp/daw`, register the connection as the active DAW; when an MCP client invokes a DAW tool, forward tool_call to that WebSocket and return the app’s tool_response.

**Test coverage:**  
- Regression: “When a DAW WebSocket is connected, stori_read_project returns project data, not ‘No DAW connected’.”  
- Integration: “After connect, send tool_call; assert tool_response with same request_id is returned to MCP client.”

**Docs:** Backend docs: ensure “register WebSocket as active DAW” and “forward tool_call” are documented.

**Accessibility:** N/A — backend only.

**MCP / Composer awareness:** Yes. Fix must register the WebSocket as active DAW on connect and forward all DAW tool calls to it. After fix, verify stori_read_project, stori_play, stori_stop from Cursor.

---

## FINAL OUTPUT
For each bug in the input list, output:

1. **Issue title** (as it would appear on GitHub).
2. **Issue body** in markdown using the sections above (Description, User journey, Where the bug is, What the fix looks like, Test coverage, Docs, Accessibility, MCP tool call awareness).
3. Suggested labels.

You can output multiple issues in one response. The user (or an agent) can then create each issue via `gh issue create --title "..." --body "..."` or the GitHub UI.
