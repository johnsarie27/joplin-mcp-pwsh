# A PROTOCOL ERROR BECOMES A JSON-RPC ERROR WITH THIS CODE. ITS MESSAGE IS WRITTEN BY THIS MODULE AND IS SAFE TO SHOW THE
# CLIENT. NO OTHER EXCEPTION'S MESSAGE EVER IS, BECAUSE IT MAY CARRY A REQUEST URL AND THE TOKEN IN ITS QUERY STRING
# (docs/design/dispatcher.md). RAISED WITH Write-Error -Exception, NEVER throw.
class McpProtocolError : System.Exception {
    [System.Int32] $Code

    McpProtocolError([System.Int32] $Code, [System.String] $Message) : base($Message) {
        $this.Code = $Code
    }
}
