# EVERY CLASS AND ENUM IN THE MODULE, IN ONE FILE (ADR 12). WITHIN ONE FILE A TYPE MAY BE USED AS A PROPERTY OR PARAMETER
# TYPE BEFORE IT IS DECLARED; ONLY A BASE CLASS MUST BE DECLARED ABOVE THE CLASSES THAT EXTEND IT. THE ROOT MODULE LOADS
# THIS FILE BEFORE ANY FUNCTION, SO EVERY FUNCTION CAN USE THESE TYPES IN ITS PARAMETERS

# WHAT A TOOL NEEDS FROM THE ACCESS OBJECT. AN ENUM, SO A TOOL REGISTERED WITHOUT ONE, OR WITH ANY OTHER VALUE, FAILS
# AT REGISTRATION (docs/design/tools.md#registration)
enum JoplinToolAccess {
    Read
    Write
    CreateNotebook
    ManageTags
}

# A PROTOCOL ERROR BECOMES A JSON-RPC ERROR WITH THIS CODE. ITS MESSAGE IS WRITTEN BY THIS MODULE AND IS SAFE TO SHOW THE
# CLIENT. NO OTHER EXCEPTION'S MESSAGE EVER IS, BECAUSE IT MAY CARRY A REQUEST URL AND THE TOKEN IN ITS QUERY STRING
# (docs/design/dispatcher.md). RAISED WITH Write-Error -Exception, NEVER throw.
class McpProtocolError : System.Exception {
    [System.Int32] $Code

    McpProtocolError([System.Int32] $Code, [System.String] $Message) : base($Message) {
        $this.Code = $Code
    }
}

# A TOOL ERROR BECOMES A RESULT WITH isError TRUE. LIKE McpProtocolError, ITS MESSAGE IS WRITTEN BY THIS MODULE AND IS SAFE
# TO SHOW THE CLIENT.
class McpToolError : System.Exception {
    McpToolError([System.String] $Message) : base($Message) { }
}

# AN ACCESS REFUSAL THE CALLER IS ENTITLED TO SEE, SUCH AS NO NOTEBOOKS BEING CONFIGURED. NEVER USED FOR A HIDDEN OR
# MISSING NOTE, WHICH MUST LOOK THE SAME (ADR 5).
class NotebookAccessError : McpToolError {
    NotebookAccessError([System.String] $Message) : base($Message) { }
}

# PLACEHOLDER ACCESS OBJECT. EVERY CHECK ANSWERS NO UNTIL CONFIG LOADING AND NOTEBOOK RESOLUTION ARE BUILT
# (docs/design/security-model.md#access-object), SO THE DISPATCHER'S GATE EXISTS AND FAILS CLOSED FROM THE START.
class NotebookAccess {
    [System.Boolean] HasAnyAccess() { return $false }
    [System.Boolean] CanRead([System.String] $NotebookId) { return $false }
    [System.Boolean] CanWrite([System.String] $NotebookId) { return $false }
    [System.Boolean] CanCreateRootNotebook() { return $false }
    [System.Boolean] CanManageTags() { return $false }
}
