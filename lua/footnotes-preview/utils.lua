local M = {}

function M.find_footnotes(bufnr)
  local footnotes = {}
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if line:match("^%[%^.+%]:") then
      table.insert(footnotes, {
        line_num = i - 1,
        text = line,
      })
    end
  end
  return footnotes
end

return M
