# A TOOL ERROR BECOMES A RESULT WITH isError TRUE. LIKE McpProtocolError, ITS MESSAGE IS WRITTEN BY THIS MODULE AND IS SAFE
# TO SHOW THE CLIENT. NotebookAccessError IS IN THE SAME FILE BECAUSE IT EXTENDS McpToolError, AND PSScriptAnalyzer PARSES
# ONE FILE AT A TIME: A BASE CLASS IN ANOTHER FILE REPORTS AS TypeNotFound.
class McpToolError : System.Exception {
    McpToolError([System.String] $Message) : base($Message) { }
}

# AN ACCESS REFUSAL THE CALLER IS ENTITLED TO SEE, SUCH AS NO NOTEBOOKS BEING CONFIGURED. NEVER USED FOR A HIDDEN OR
# MISSING NOTE, WHICH MUST LOOK THE SAME (ADR 5).
class NotebookAccessError : McpToolError {
    NotebookAccessError([System.String] $Message) : base($Message) { }
}
