local M = {}

function M.setup()
  vim.api.nvim_create_user_command("FootnotesPreview", function()
    require("footnotes-preview.sidebar").open()
  end, {})

  vim.keymap.set("n", "<leader>fn", "<cmd>FootnotesPreview<CR>", { desc = "Preview Footnotes" })
end

return M
