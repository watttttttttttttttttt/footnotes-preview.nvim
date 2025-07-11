local utils = require("footnotes-preview.utils")
local M = {}

local win, buf

function M.open()
  local current_buf = vim.api.nvim_get_current_buf()
  local footnotes = utils.find_footnotes(current_buf)

  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end

  buf = vim.api.nvim_create_buf(false, true)

  local footnote_lines = {}
  for i, note in ipairs(footnotes) do
    table.insert(footnote_lines, string.format("%d: %s", i, note.text))
  end

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, footnote_lines)
  vim.api.nvim_buf_set_option(buf, "filetype", "footnotes")

  local width = math.floor(vim.o.columns * 0.3)
  win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = vim.o.lines - 4,
    row = 2,
    col = vim.o.columns - width - 1,
    style = "minimal",
    border = "rounded",
  })

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = cursor[1]
    local target = footnotes[line]
    if target then
      vim.api.nvim_set_current_win(vim.fn.bufwinid(current_buf))
      vim.api.nvim_win_set_cursor(0, { target.line_num + 1, 0 })
    end
  end, { buffer = buf })
end

return M
