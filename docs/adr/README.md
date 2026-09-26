# Architecture decision records

One page per structural decision: the context, the decision, the alternatives
considered, the consequences. A record is never edited after acceptance; a
change is a new record that supersedes it. Numbering is chronological.

| # | Decision | Status |
|---|---|---|
| [0001](0001-keep-the-c-host-and-lua-5.1.md) | Keep the C host and Lua 5.1 for the 2.0 core | proposed |
| [0002](0002-rewrite-not-patch.md) | Rewrite the application from scratch instead of patching it further | proposed |
| [0003](0003-event-loop-and-pure-handlers.md) | One event loop, pure handlers, ports and adapters | proposed |
| [0004](0004-keep-1x-data-files.md) | Keep the 1.x data files and formats (reversibility) | proposed |
| [0005](0005-contract-v2.md) | A versioned contract with revisioned state and typed errors; v1 kept one release | proposed |
| [0006](0006-third-party-code.md) | Third-party code: minimal, vendored, pinned | proposed |
| [0007](0007-security-model.md) | Close root execution over HTTP; bind MQTT to localhost; password on the WebSocket | proposed |
| [0008](0008-no-shell-in-the-hot-loop.md) | No shell processes or temp files in the loop | proposed |
| [0009](0009-keep-spotify-deezer.md) | Keep Spotify Connect and Deezer as an optional module | accepted |
