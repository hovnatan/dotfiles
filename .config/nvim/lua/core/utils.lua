function P(cmd)
  print(vim.inspect(cmd))
end

function _G.safe_require(module)
  local ok, result = pcall(require, module)
  if not ok then
    vim.notify(string.format('Error requiring: %s', module), vim.log.levels.ERROR)
    return ok
  end
  return result
end

function _G.fsize(file)
  local current = file:seek() -- get current position
  local size = file:seek("end") -- get file size
  file:seek("set", current) -- restore position
  return size
end
