
globals = {
  "serpent",
  data = {
    other_fields = true,
  },
  "remote",
  "game",
  "global",
  "mods",
  "commands",
  "rendering",
  "pipecoverspictures",
}

read_globals = {
  "log",
  "table_size",
  defines = {
    other_fields = true,
  },
  "script",
  "settings",
  table = {
    fields = {
      deepcopy = {}
    }
  }
}

ignore = {
  -- ignore "Unused argument" (callback functions)
  "212",
  -- ignore "Line is too long"
  "631"
}
