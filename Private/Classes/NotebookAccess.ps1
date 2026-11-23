# PLACEHOLDER ACCESS OBJECT. EVERY CHECK ANSWERS NO UNTIL CONFIG LOADING AND NOTEBOOK RESOLUTION ARE BUILT
# (docs/design/security-model.md#access-object), SO THE DISPATCHER'S GATE EXISTS AND FAILS CLOSED FROM THE START.
class NotebookAccess {
    [System.Boolean] HasAnyAccess() { return $false }
    [System.Boolean] CanRead([System.String] $NotebookId) { return $false }
    [System.Boolean] CanWrite([System.String] $NotebookId) { return $false }
    [System.Boolean] CanCreateRootNotebook() { return $false }
    [System.Boolean] CanManageTags() { return $false }
}
