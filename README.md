# NX CORE

**Core framework resource for NOVARA CITY FiveM server.**

`nx_core` is a modular FiveM resource containing client-side, server-side, and shared components for the NOVARA CITY server ecosystem.

## Features

- Modular client and server structure
- Player state handling
- Client focus management
- Shared configuration

## Requirements

- FiveM server
- Compatible NOVARA CITY resources

## Installation

1. Download or clone this repository.
2. Place the `nx_core` folder inside your server's `resources` directory.
3. Review `shared/config.lua`.
4. Add the following line to your `server.cfg`:

   ```cfg
   ensure nx_core
   ```

5. Restart the server and check the console for errors.

## Resource Structure

```text
nx_core/
├── fxmanifest.lua
├── client/
│   ├── main.lua
│   └── focus.lua
├── server/
│   ├── main.lua
│   └── state.lua
└── shared/
    └── config.lua
```

## Compatibility

Developed for the FiveM platform. Compatibility with other resources must be verified in your server environment.

## License

No license has been provided. All rights are reserved by default unless the copyright holder grants permission otherwise.

## Project

**NOVARA CITY** — FiveM Roleplay
