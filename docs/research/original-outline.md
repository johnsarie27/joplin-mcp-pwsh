# Original outline (superseded)

**Status:** superseded by the design in [`docs/design/`](../design/overview.md). Kept for history.

This is the first revision of the design issue ([#1](https://github.com/johnsarie27/joplin-mcp-pwsh/issues/1)), preserved verbatim. What changed since:

- **Port discovery is dropped.** `host` and `port` come from config, as in the Python server ([config.md](../design/config.md)).
- **Tool names** follow the Python server (`search_notes`, `create_note`, ...) rather than the `joplin_` prefix used here ([tools.md](../design/tools.md)).
- **The protocol host** is a thin core written for this project, not Kevin Marquette's tooling host ([ADR 7](../adr/0007-thin-core-no-framework.md)).
- **Error handling** returns `isError` results with sanitized text, not `{ "error": ... }` objects ([dispatcher.md](../design/dispatcher.md#error-conventions)).

Still potentially useful: the Joplin REST endpoint notes in Phase 2 (for example, that `DELETE /notes/:id` moves a note to the trash unless `permanent=1`, and that `POST /notes` accepts `body_html`). These have **not been verified** against the Joplin API docs for this project, and the bracketed citations `[1]`–`[15]` refer to a source list that was never included in the issue.

---
This outline details the architecture, file layout, and step-by-step implementation for building a custom Model Context Protocol (MCP) server for Joplin using PowerShell, based on Kevin Marquette's tooling host methodology [1, 2] and the Joplin REST Data API [3].

---

### 1. File List & Project Structure

```text
JoplinMCPServer/
├── config.json                     # Environment config (Auth token, default port, log settings)
├── Start-JoplinMCPServer.ps1       # Main entry point: STDIO JSON-RPC loop & tool router
├── JoplinMCPServer.psd1            # PowerShell Module Manifest
├── JoplinMCPServer.psm1            # Root Module loading sub-scripts
└── Public/
    ├── Joplin-Connection.ps1       # Port discovery (pinging 41184–41194) & REST wrapper
    ├── Joplin-Notes.ps1            # Handlers for note operations (/notes, /search)
    ├── Joplin-Notebooks.ps1        # Handlers for notebook management (/folders)
    └── Joplin-Tags.ps1             # Handlers for tag assignments (/tags)
```

---

### 2. Architecture & Communication Flow

```text
+------------------+                    +---------------------------+                    +---------------------------+
|    LLM Client    |  --- STDIO (JSON) -> |   PowerShell MCP Host    |  -- HTTP / REST -> |  Joplin Clipper Server    |
| (Claude/VS Code) |  <- JSON-RPC Resp --  | (Kevin Marquette Pattern) |  <- JSON Response - | (localhost:41184-41194)   |
+------------------+                    +---------------------------+                    +---------------------------+
```

* **LLM Layer**: Communicates via standard input/output (STDIO) using standard JSON-RPC 2.0 protocol format.
* **PowerShell Host Layer**: Acts as a secure middleware layer [1, 2]. It receives MCP JSON requests, validates inputs, and executes strictly predefined PowerShell functions rather than evaluating arbitrary script commands [2].
* **Joplin Local Service**: Receives REST HTTP requests (GET, POST, PUT, DELETE) on the discovered local port, authenticated with a security token [4, 5].

---

### 3. Implementation Instructions

#### Phase 1: Authentication & Port Discovery Setup
1. **Retrieve Security Token**: Obtain the Clipper token from Joplin Desktop (*Tools > Options > Web Clipper*) [4]. Store this token in `config.json` [4].
2. **Implement Dynamic Port Scanner (`Joplin-Connection.ps1`)**:
   * Loop through ports **41184** to **41194** [3, 4].
   * Query `GET http://localhost:<port>/ping` [4, 6].
   * Set the active port when the response string matches `"JoplinClipperServer"` [4, 6].
3. **Build Authenticated Request Helper**:
   * Wrap `Invoke-RestMethod` to automatically append `?token=<your_token>` to every outbound URL [4, 7].
   * Configure default content types to `application/json` and handle JSON body conversion [7].

#### Phase 2: Core Tool Command Implementation
Expose focused PowerShell functions that translate tool parameters into Joplin REST calls:

* **Note Management (`Joplin-Notes.ps1`)**:
  * `joplin_search`: Call `GET /search?query=<query>` with field selection (`fields=id,title,parent_id`) [6, 8]. Support pagination parameters (`page`, `limit`) [9].
  * `joplin_create_note`: Send a JSON payload containing `title`, `body` (Markdown), or `body_html` to `POST /notes` [7, 10].
  * `joplin_update_note`: Call `PUT /notes/:id` with updated fields (`title`, `body`, or `parent_id` to move notebooks) [5, 11, 12].
  * `joplin_delete_note`: Call `DELETE /notes/:id` (moves to trash by default, or permanent via `permanent=1`) [12].
* **Notebook Management (`Joplin-Notebooks.ps1`)**:
  * `joplin_list_notebooks`: Call `GET /folders` to retrieve the notebook folder hierarchy [13].
  * `joplin_create_notebook`: Send `title` and optional `parent_id` to `POST /folders` [12, 13].
* **Tagging Operations (`Joplin-Tags.ps1`)**:
  * `joplin_get_tags`: Call `GET /tags` [14].
  * `joplin_tag_note`: Post note ID to `POST /tags/:id/notes` [14].

#### Phase 3: MCP Protocol & STDIO Server Engine (`Start-JoplinMCPServer.ps1`)
1. **Initialize Standard I/O**: Open a standard input listener loop in PowerShell (`[Console]::In.ReadLine()`).
2. **Register Protocol Handlers**:
   * **`initialize`**: Return MCP server capabilities and protocol version.
   * **`tools/list`**: Output JSON schemas defining the available tools (`joplin_search`, `joplin_create_note`, etc.) and their parameter requirements.
   * **`tools/call`**: Intercept tool execution calls, parse arguments, pass them to the target PowerShell function, and encode the function output into an MCP content response object.
3. **Error Handling & Resilience**:
   * Catch HTTP status codes >= 400 from Joplin and format errors as JSON objects (`{ "error": "description" }`) for the LLM [15].
