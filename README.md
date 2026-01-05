# todoer.nvim

Minimalistic todo and task tracker plugin based on your TODOs in code for Neovim written in Lua.

## Features

- Command for Neovim to list all TODOs in the current project.
    - Jump to the location of a TODO directly from the list.
    - Create a task from TODO. And move it accross different statuses.
- Create a task withoud TODO in code.
- Everything is rendered in readonly custom buffer with rendered links to files and commands to interact with tasks and navigate projects TODOs.

## Task

- Metadata with:
    - Creation date (required)
    - Status (OPEN, IN_PROGRESS, DONE) (required)
    - Priority (LOW, MEDIUM, HIGH) (required; default: MEDIUM)
    - Positions entries containing file path and line number of the TODO in code. (optional)
- Description with:
    - Title is a tag from `TODO:[tag]` mark in code. If no tag provided title is the date of task creation.
    - Text from `TODO:[tag] [multiline text]` mark in code.

