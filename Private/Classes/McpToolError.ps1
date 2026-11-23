# A TOOL ERROR BECOMES A RESULT WITH isError TRUE. LIKE McpProtocolError, ITS MESSAGE IS WRITTEN BY THIS MODULE AND IS SAFE
# TO SHOW THE CLIENT.
class McpToolError : System.Exception {
    McpToolError([System.String] $Message) : base($Message) { }
}
