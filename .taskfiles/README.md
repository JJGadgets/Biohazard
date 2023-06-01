# Taskfiles

Similar to shell scripts and functions, but potentially lesser OS dependencies (has an embedded sh interpreter in the single Go binary `task`) and easy to have directory/project-specific tasks/aliases/functions.

{{.var}} replaces `sh`/`bash` ${var} for Task-managed variables (within cmds, ${var} can sometimes still be used for shell-managed variables depending on how it's done)

Pairs well with: `yq`, `envsubst`, and other CLI tools.
