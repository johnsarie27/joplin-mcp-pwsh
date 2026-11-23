# Tools

How tools are registered, what `tools/list` publishes, and the access check each tool performs.

## Registration

Every tool is registered with a name, a description, a mandatory `Access` value, a strict input schema and a handler scriptblock. The handler receives the validated arguments and the resolved `[NotebookAccess]` ([security-model.md](security-model.md#access-object)).

```powershell
Register-JoplinTool `
    -Name        'search_notes' `
    -Description 'Search Joplin notes by keyword. Returns matching note titles and ids. Searches only notebooks the server has been granted access to.' `
    -Access      Read `
    -InputSchema @{
        type                 = 'object'
        properties           = @{
            query = @{ type = 'string'; description = 'Search keywords.'; minLength = 1 }
            limit = @{ type = 'integer'; description = 'Max results per page.'; minimum = 1; maximum = 100; default = 20 }
        }
        required             = @('query')
        additionalProperties = $false
    } `
    -Handler {
        param([hashtable] $Arguments, [NotebookAccess] $Access)
        # Select-ReadableNotes pages through Joplin's results (bounded page cap), keeps only readable
        # notes and fills the requested page size. Counts and "more results" reflect what the caller
        # can see, never the raw page (ADR 5).
        $found = Select-ReadableNotes -Access $Access -Path '/search' -Limit ($Arguments.limit ?? 20) `
                     -Query @{ query = $Arguments.query; fields = 'id,title,parent_id' }
        Format-SearchResult -Query $Arguments.query -Items $found.Items -HasMore $found.HasMore
    }
```

Registration rules:

- `Access` is one of `Read`, `Write`, `CreateNotebook`, `ManageTags`. A tool without it fails registration. It may be declared as a parameter (above) or as an attribute on the handler function, in the style of pwsh.mcp's `[Annotations()]`.
- `Access` drives the MCP `readOnlyHint` annotation (`Read` is read-only).
- Every schema sets `additionalProperties: false`; ids use the pattern `^[0-9a-f]{32}$`; no empty `required` array is emitted.
- A description is mandatory and must be of useful length; registration never falls back to the tool name. Descriptions of tools that filter by access carry the static scope statement ([access-control.md](access-control.md#information-hiding)).
- Handlers return exactly one value, normally a formatted string.

## What `tools/list` returns

The registry serializes each entry to the MCP tool shape (`name`, `description`, `inputSchema`, optional `annotations`):

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "search_notes",
        "description": "Search Joplin notes by keyword. Returns matching note titles and ids. Searches only notebooks the server has been granted access to.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "query": { "type": "string", "description": "Search keywords.", "minLength": 1 },
            "limit": { "type": "integer", "description": "Max results per page.", "minimum": 1, "maximum": 100, "default": 20 }
          },
          "required": ["query"],
          "additionalProperties": false
        },
        "annotations": { "readOnlyHint": true }
      },
      {
        "name": "update_note_section",
        "description": "Replace one exact occurrence of old_str in a note's body with new_str. Fails if old_str is missing or ambiguous.",
        "inputSchema": {
          "type": "object",
          "properties": {
            "note_id": { "type": "string", "pattern": "^[0-9a-f]{32}$" },
            "old_str": { "type": "string", "minLength": 1 },
            "new_str": { "type": "string" }
          },
          "required": ["note_id", "old_str", "new_str"],
          "additionalProperties": false
        },
        "annotations": { "readOnlyHint": false, "destructiveHint": true }
      }
    ]
  }
}
```

**Schema snapshot.** `Start-JoplinMcpServer -ListTools` prints the `result` object of `tools/list`, `{"tools":[...]}` as compact JSON, and exits without starting the loop (the idea comes from pwsh.mcp's `-WhatIf` dry run). Tools are ordered by name and schema keys are sorted, so the output is the same on every run. A golden-file test, `Tests/Registry/tools-list.golden.json`, compares that output, so any change to a published tool schema shows up in review.

## Inventory

13 tools from the Python server plus 5 tag tools ([ADR 3](../adr/0003-root-and-tags-sentinels.md)).

| Tool | Access | Check |
|---|---|---|
| `search_notes` | Read | `Select-ReadableNotes` post-filter by `parent_id`; filtered pagination |
| `get_note` | Read | `Get-AccessibleNote` (`CanRead(note.parent_id)`); hidden = not found |
| `list_notes_in_notebook` | Read | `CanRead(notebook_id)`; denied or unreadable behaves like a nonexistent notebook |
| `list_notebooks` | Read | omit notebooks the caller cannot read; no count of omitted entries |
| `list_tags` | Read | none (tags are not notebook-scoped; tag-name leak accepted, ADR 3) |
| `get_notes_by_tag` | Read | `Select-ReadableNotes` post-filter by `parent_id` |
| `create_note` | Write | `CanWrite(notebook_id)` |
| `update_note` | Write | `Get-AccessibleNote` (`CanWrite(note.parent_id)`) |
| `update_note_section` | Write | `Get-AccessibleNote` (`CanWrite(note.parent_id)`) |
| `append_note_section` | Write | `Get-AccessibleNote` (`CanWrite(note.parent_id)`) |
| `delete_note` | Write | `Get-AccessibleNote` (`CanWrite(note.parent_id)`) |
| `complete_todo` | Write | `Get-AccessibleNote` (`CanWrite(note.parent_id)`) |
| `create_notebook` | CreateNotebook | `CanWrite(parent_id)` or, with no parent, `CanCreateRootNotebook()` |
| `create_tag` | ManageTags | `CanManageTags()` |
| `rename_tag` | ManageTags | `CanManageTags()` |
| `delete_tag` | ManageTags | `CanManageTags()` and refused if the tag is attached to any note outside the caller's writable notebooks (reports a count only) |
| `tag_note` | Write | `CanWrite(note.parent_id)` |
| `untag_note` | Write | `CanWrite(note.parent_id)` |

### `list_notebooks` differs from the Python server

At the time the design was written, the Python server's `server.py` implemented `list_notebooks` as a plain `get_client().list_notebooks()` with no `_require_access()` and no `can_read` filter, so it returns every notebook's title and id, including notebooks the config never grants. That was a deliberate choice (johnsarie27/joplin-mcp#1: "metadata only, not note content").

Once deny rules exist, a denied notebook's name would still be visible to the caller, so this server filters instead. Because write implies read, every notebook the caller can write to still appears, so the ids needed by `create_note` and `create_notebook` stay discoverable. Whether the Python server should adopt the same filtering is an open question in johnsarie27/joplin-mcp#68.

### Tag mutation

`create_tag`, `rename_tag`, `delete_tag`, `tag_note` and `untag_note` come from [ADR 3](../adr/0003-root-and-tags-sentinels.md). That decision settles, for this server, the access-control question blocking johnsarie27/joplin-mcp#28 and the root-notebook question in johnsarie27/joplin-mcp#17.
