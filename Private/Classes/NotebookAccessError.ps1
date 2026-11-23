# AN ACCESS REFUSAL THE CALLER IS ENTITLED TO SEE, SUCH AS NO NOTEBOOKS BEING CONFIGURED. NEVER USED FOR A HIDDEN OR
# MISSING NOTE, WHICH MUST LOOK THE SAME (ADR 5).
class NotebookAccessError : McpToolError {
    NotebookAccessError([System.String] $Message) : base($Message) { }
}
