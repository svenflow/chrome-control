# chrome-control

Control Chrome from the command line via a native messaging extension.

## Architecture

```
┌─────────────────┐     stdio      ┌──────────────┐   Unix socket   ┌─────┐
│ Chrome Extension │◄──────────────►│ Native Host  │◄───────────────►│ CLI │
│ (background.js)  │               │ (Python)     │                 │     │
└─────────────────┘                └──────────────┘                 └─────┘
```

The Chrome extension communicates with a native messaging host over stdio. The native host listens on a Unix socket. The CLI sends JSON commands to the socket and receives responses. This persistent socket connection means zero startup overhead per command.

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
chrome type <tab_id> <ref> <text>        Type text into element
chrome input <tab_id> <ref> <value>      Set form input value
chrome key <tab_id> <key> [modifiers]    Send key press (e.g. Enter, Tab, Escape)
chrome scroll <tab_id> <direction>       Scroll page (up, down, left, right)
chrome hover <tab_id> <x> <y>           Hover at coordinates
```

### Screenshots

```
chrome screenshot <tab_id>               Save screenshot to ~/Pictures/chrome-screenshots/
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

### CSP Bypass

These commands use the Chrome Debugger API with `Page.createIsolatedWorld` and `grantUniversalAccess` to work on pages with strict Content Security Policy (CSP), Trusted Types, and cross-origin iframes.

```
chrome iframe-click <tab_id> <selector>  Click element in any frame by CSS selector
chrome insert-text <tab_id> <text>       Insert text at current focus (works in iframes)
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

## License

MIT
