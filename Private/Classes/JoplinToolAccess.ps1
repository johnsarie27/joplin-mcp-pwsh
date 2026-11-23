# WHAT A TOOL NEEDS FROM THE ACCESS OBJECT. AN ENUM, SO A TOOL REGISTERED WITHOUT ONE, OR WITH ANY OTHER VALUE, FAILS
# AT REGISTRATION (docs/design/tools.md#registration)
enum JoplinToolAccess {
    Read
    Write
    CreateNotebook
    ManageTags
}
