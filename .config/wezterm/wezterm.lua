local wezterm = require 'wezterm';

return {
  color_scheme = "Gruvbox Light",
  font = wezterm.font("JetBrains Mono"),
  font_size = 16.0,
  hide_tab_bar_if_only_one_tab = true,
  disable_default_key_bindings = true,
  keys = {
    {key="J", mods="CMD", action=wezterm.action{SendString="\x1bj"}},
    {key="K", mods="CMD", action=wezterm.action{SendString="\x1bk"}},
    {key="H", mods="CMD", action=wezterm.action{SendString="\x1bh"}},
    {key="L", mods="CMD", action=wezterm.action{SendString="\x1bl"}},
    {key="Q", mods="CMD", action=wezterm.action{SendString="\x1bq"}},
    {key="J", mods="CMD|SHIFT", action=wezterm.action{SendString="\x1bJ"}},
    {key="K", mods="CMD|SHIFT", action=wezterm.action{SendString="\x1bK"}},
    {key="H", mods="CMD|SHIFT", action=wezterm.action{SendString="\x1bH"}},
    {key="L", mods="CMD|SHIFT", action=wezterm.action{SendString="\x1bL"}},
    {key="C", mods="CMD|SHIFT", action=wezterm.action{CopyTo="Clipboard"}},
    {key="V", mods="CMD|SHIFT", action=wezterm.action{PasteFrom="Clipboard"}},
  }
}
