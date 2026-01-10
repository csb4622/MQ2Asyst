# Asyst — MacroQuest Lua Automation Plugin

## Overview

**Asyst** is a modular MacroQuest Lua plugin intended to automate character behavior in EverQuest while providing a structured, maintainable UI using Dear ImGui.

The project emphasizes:
- Clear separation of concerns
- Minimal shared state
- Deterministic UI rendering
- Extensible automation services

The current implementation provides a UI framework, character snapshotting, logging, and tab-based configuration. Automation logic is intentionally stubbed and will be layered in incrementally.

---

## Goals

- Automate common character behaviors (assist, follow, combat, utility)
- Maintain a stable, readable Lua codebase despite MQ constraints
- Avoid monolithic scripts
- Keep UI, state, and automation logic decoupled
- Remain safe, predictable, and debuggable in-game

---

## Non-Goals

- No deep inheritance trees
- No hidden magic or global state abuse
- No attempt to emulate full OOP systems
- No dependency on non-MQ Lua frameworks

---

## Architecture Overview

The project follows a composition-first design:

- Entry Point  
  Responsible only for wiring and lifecycle.

- App  
  Composition root. Owns services, state, UI, and the main loop.

- State  
  Centralized mutable state container. No behavior.

- Services  
  Read-only or action-oriented logic (e.g., character info, automation).

- UI  
  Immediate-mode rendering only. No business logic.

- Tabs  
  One responsibility per tab. Stateless except for shared state access.

- Utilities  
  Logging and shared helpers.

This structure mirrors SOLID principles as closely as practical in Lua.

---

## Directory Layout

```
asyst/
  init.lua                -- Entry point
  App.lua                 -- Composition root & lifecycle
  State.lua               -- Shared state container

  services/
    CharacterService.lua  -- Character snapshot (name, level, class)

  ui/
    AsystWindow.lua       -- Main window + header + tabs
    tabs/
      GeneralTab.lua
      OptionsTab.lua
      ConsoleTab.lua

  util/
    Logger.lua             -- Logging + UI console sink
```

---

## Lifecycle

1. Initialization
   - Capture character snapshot (name, level, class)
   - Register MQ commands
   - Initialize UI state

2. Runtime
   - mq.imgui.init() drives UI rendering
   - Main loop keeps script alive
   - UI reads state; automation will act on state

3. Shutdown
   - Graceful exit when UI closes or MQ unloads

---

## UI Design

- Immediate-mode (Dear ImGui)
- Stateless rendering
- Header format:

```
Asyst - <ClassName>
```

- Tabs:
  - General – character info and status
  - Options – automation toggles (stub)
  - Console – in-plugin logging output

---

## Character Data Model

Character data is captured once at startup and stored as a snapshot:

```
character = {
  name = string,
  level = number,
  className = string,
  classShortName = string,
}
```

Live TLO access is intentionally avoided in UI code to reduce coupling.

---

## Logging

- Centralized logger
- Emits to MQ chat
- Optionally mirrors output into the UI Console tab
- Bounded history to prevent memory growth

---

## Automation (Planned)

Automation will be implemented as discrete services:

- AutomationEngine (tick-based)
- CombatService
- AssistService
- FollowService
- MovementService

Each service will:
- Read state
- Make deterministic decisions
- Execute explicit MQ actions
- Fail safely

No automation logic will live in UI code.

---

## Design Rules

- `return <module>` must be the final line of every Lua module
- No globals unless MQ requires them
- UI never mutates game state directly
- Services do not render UI
- State contains no logic
- Prefer clarity over cleverness

---

## Requirements

- MacroQuest
- Lua support enabled
- Dear ImGui (MQ built-in)

---

## Status

Early scaffold / UI foundation

- UI framework: complete
- Character snapshot: complete
- Automation: not implemented yet

---

## Next Steps

- Add AutomationEngine.lua
- Implement safe tick loop
- Add first real behavior (assist or follow)
- Persist options across sessions
- Add class-aware UI styling
