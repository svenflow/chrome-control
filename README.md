# chrome-control

Browser automation CLI designed for AI agents. Built for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) but works with any LLM or script that can call shell commands.

Every command is a single shell call that returns structured text — no SDK, no library imports, no async/await. This makes it trivial for an AI agent to read pages, click elements, fill forms, and take screenshots by generating shell commands.

```
┌──────────┐     shell      ┌─────────────────┐     stdio      ┌──────────────┐
│ AI Agent │───────────────►│ chrome CLI       │───────────────►│ Chrome       │
│ (Claude) │◄───────────────│ (Unix socket)    │◄───────────────│ (Extension)  │
└──────────┘   text output  └─────────────────┘   native msg   └──────────────┘
```

## Why This Exists

Browser automation libraries (Playwright, Selenium) are designed for developers writing code. They're fast but require in-process SDK calls — an AI agent can't use them without writing and executing a Python/JS program for every action.

chrome-control flips this: every operation is a CLI command with text output. An AI agent can:

```bash
# Read what's on the page
chrome read 12345              # → ref_1  button  Sign In
                               #   ref_2  input   Email

# Interact with elements by reference
chrome type 12345 ref_2 "user@example.com"
chrome click 12345 ref_1

# Handle CSP-protected sites that block normal automation
chrome iframe-click 12345 'input[type="password"]'
chrome insert-text 12345 "password123"
```

No imports. No boilerplate. Just shell commands an LLM can generate naturally.

## Architecture

```
┌─────────────────┐     stdio      ┌──────────────┐   Unix socket   ┌─────┐
│ Chrome Extension │◄──────────────►│ Native Host  │◄───────────────►│ CLI │
│ (background.js)  │               │ (Python)     │                 │     │
└─────────────────┘                └──────────────┘                 └─────┘
```

The Chrome extension communicates with a native messaging host over stdio. The native host listens on a Unix socket. The CLI sends JSON commands to the socket and receives responses. This persistent socket connection means zero startup overhead per command.

## Requirements

- macOS (Linux/Windows support planned)
- Chrome or Chromium browser
- Python 3.6+
- `sips` (ships with macOS — used for screenshot resizing; screenshots still work without it, just unresized)

## Benchmark

Median of 3 runs on Mac Mini M4 Pro:

| Test          | chrome-control | browser-use | Playwright | Selenium |
|---------------|---------------|-------------|------------|----------|
| Navigation    | 1,342ms       | 3,296ms     | 304ms      | 174ms    |
| Elements      | 1,578ms       | 3,677ms     | 607ms      | 395ms    |
| JS Execution  | 1,225ms       | 3,004ms     | 104ms      | 51ms     |
| CSP Bypass    | 1,412ms       | 13,981ms    | 4,284ms    | 2,944ms  |
| Screenshot    | 1,551ms       | 11,176ms    | 120ms      | 133ms    |

chrome-control numbers are from a run where the socket was warm (from earlier benchmark). Playwright and Selenium are faster on raw operations because they use in-process CDP connections. browser-use spawns a new process per command.

**However**, chrome-control's key advantage is CSP bypass and cross-origin iframe handling that Playwright and Selenium cannot do. The CSP test only measures text extraction -- it doesn't test the hard cases (clicking inside cross-origin iframes, typing into secure payment fields, bypassing Trusted Types).

## Quick Start

```bash
# 1. Load the extension in Chrome
#    chrome://extensions -> Developer mode -> Load unpacked -> select extension/

# 2. Install the native messaging host
./scripts/install.sh

# 3. Use the CLI
./scripts/chrome tabs
./scripts/chrome open "https://example.com"
```

## Commands

### Tab Management

```
chrome tabs                              List open tabs
chrome open <url>                        Open new tab
chrome close <tab_id>                    Close tab
chrome focus <tab_id>                    Focus/activate tab
chrome navigate <tab_id> <url>           Navigate tab (also: back, forward)
```

### Page Reading

```
chrome read <tab_id> [filter]            Read interactive elements (filters: interactive, all, forms, links)
chrome text <tab_id>                     Get page text content
chrome html <tab_id>                     Get page HTML
chrome find <tab_id> <query>             Find elements by text
```

### Interaction

```
chrome click <tab_id> <ref>              Click element by ref (e.g. ref_1)
chrome click-at <tab_id> <x> <y>        Click at viewport coordinates
chrome click-by-name <tab_id> <name>    Click by accessible name (bypasses CSP)
chrome type <tab_id> <ref> <text>        Type text into element
chrome input <tab_id> <ref> <value>      Set form input value
chrome key <tab_id> <key> [modifiers]    Send key press (e.g. Enter, Tab, Escape)
chrome scroll <tab_id> <direction>       Scroll page (up, down, left, right)
chrome hover <tab_id> <x> <y>           Hover at coordinates
```

### Screenshots

```
chrome screenshot <tab_id>               Save screenshot to ~/Pictures/chrome-screenshots/
chrome shot <tab_id>                     Alias for screenshot
```

### JavaScript

```
chrome js <tab_id> <code>                Execute JavaScript in page context
```

### Debugging

```
chrome console <tab_id> [pattern]        Read console messages (--clear to flush)
chrome network <tab_id> [url_pattern]    Read network requests (--clear to flush)
```

### Cookies

```
chrome cookies <domain>                  Get all cookies for a domain (including HttpOnly)
```

### CSP Bypass

These commands use the Chrome Debugger API with `Page.createIsolatedWorld` and `grantUniversalAccess` to work on pages with strict Content Security Policy (CSP), Trusted Types, and cross-origin iframes.

```
chrome iframe-click <tab_id> <selector>  Click element in any frame by CSS selector
chrome iframe-type <tab_id> <text>       Type text via debugger key events (works in iframes)
chrome iframe-eval <tab_id> <url_pattern> <code>  Execute JS inside a cross-origin iframe
chrome insert-text <tab_id> <text>       Insert text at current focus (works in iframes)
chrome js-all-frames <tab_id> <code>     Execute JS in ALL frames (including cross-origin)
```

`iframe-click` also supports text-based selectors:

```bash
chrome iframe-click 123456 'text:Sign In'
chrome iframe-click 123456 'input[type="password"]'
```

### Multi-Profile

Supports multiple Chrome profiles simultaneously. Each profile gets its own socket.

```
chrome profiles                          List connected profiles
chrome -p <name|index> <command>         Target specific profile
```

## CSP & Cross-Origin Iframe Bypass

This is the key differentiator over Playwright and Selenium.

Many sites use strict Content Security Policy or cross-origin iframes that block normal automation:
- Discord (Trusted Types blocks `eval()`)
- Google Cloud Console
- Apple Sign-In iframes
- Google OAuth flows

chrome-control bypasses these restrictions using the Chrome Debugger API:

- **`Page.createIsolatedWorld`** with `grantUniversalAccess` executes JavaScript inside cross-origin iframes, bypassing CSP entirely.
- **`iframe-click`** dispatches a full mouse event sequence (`mouseenter` -> `mouseover` -> `mousemove` -> `mousedown` -> `mouseup` -> `click`) to bypass bot detection that checks for synthetic events.
- **`insert-text`** types into focused elements inside cross-origin iframes where normal JS injection fails.

## Troubleshooting

**"Connection refused" or "Socket not found"**
The native messaging host isn't running. Check that the extension is loaded and enabled in Chrome. Reload it from `chrome://extensions`.

**Commands hang or timeout**
The native host may have crashed. Check the log at `/tmp/chrome_control.log`. Reload the extension to restart it.

**"Extension not found" during install**
Make sure you loaded the extension in Chrome first (chrome://extensions → Load unpacked → select the `extension/` directory).

**Permission denied on socket**
The socket at `/tmp/chrome_control_*.sock` must be owned by your user. Remove stale sockets: `rm /tmp/chrome_control_*.sock`

## Security

The extension requires these Chrome permissions:
- **`debugger`** — Full Chrome DevTools Protocol access. Required for CSP bypass (createIsolatedWorld) and screenshots. This is the most powerful Chrome permission.
- **`tabs`** — Tab enumeration and management.
- **`cookies`** — Cookie read/write access.
- **`<all_urls>`** — Content script injection on any page.

The native messaging host listens on a Unix socket at `/tmp/chrome_control_<profile_id>.sock` with owner-only permissions (0o700). Any process running as your user can connect to this socket and control Chrome.

**For production use:** Lock `allowed_origins` in the native messaging manifest to your specific extension ID instead of the wildcard `chrome-extension://*`.

## License

MIT
