local M = {}

M.hotkeys = {
  {
    type = "custom-input",
    name = "golem-open-gui",
    key_sequence = "mouse-button-1",
  },
}

data:extend( M.hotkeys )
