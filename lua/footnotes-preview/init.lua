-- lua/footnotes-preview/init.lua
local M = {}

-- Default configuration
local config = {
  sidebar_width = 50,
  sidebar_position = 'right', -- 'left' or 'right'
  auto_open = false,
  auto_close = true,
  keymaps = {
    toggle_sidebar = '<leader>fn',
    edit_footnote = '<CR>',
    delete_footnote = 'dd',
    new_footnote = 'o',
    save_and_close = '<C-s>',
    cancel_edit = '<Esc>',
    jump_to_reference = 'gd',
  },
  highlight_groups = {
    footnote_id = 'Identifier',
    footnote_text = 'Normal',
    footnote_separator = 'Comment',
    current_line = 'CursorLine',
  }
}

-- Plugin state
local state = {
  sidebar_win = nil,
  sidebar_buf = nil,
  edit_win = nil,
  edit_buf = nil,
  source_buf = nil,
  footnotes = {},
  current_footnote = nil,
  is_editing = false,
}

-- Utility functions
local function create_buffer(name, options)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  
  if options then
    for option, value in pairs(options) do
      vim.api.nvim_buf_set_option(buf, option, value)
    end
  end
  
  return buf
end

local function create_window(buf, win_config)
  local win = vim.api.nvim_open_win(buf, false, win_config)
  return win
end

local function close_window(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function get_footnotes_from_buffer(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local footnotes = {}
  
  for i, line in ipairs(lines) do
    -- Match footnote definitions: [^id]: content
    local id, content = line:match("^%[%^([^%]]+)%]:%s*(.*)$")
    if id and content then
      footnotes[id] = {
        id = id,
        content = content,
        line = i,
        references = {}
      }
    end
  end
  
  -- Find footnote references: [^id]
  for i, line in ipairs(lines) do
    for id in line:gmatch("%[%^([^%]]+)%]") do
      if footnotes[id] then
        table.insert(footnotes[id].references, i)
      end
    end
  end
  
  return footnotes
end

local function update_sidebar_content()
  if not state.sidebar_buf or not vim.api.nvim_buf_is_valid(state.sidebar_buf) then
    return
  end
  
  local content = {}
  local footnote_ids = {}
  
  -- Sort footnotes by their line numbers
  for id, footnote in pairs(state.footnotes) do
    table.insert(footnote_ids, id)
  end
  
  table.sort(footnote_ids, function(a, b)
    return state.footnotes[a].line < state.footnotes[b].line
  end)
  
  -- Generate sidebar content
  table.insert(content, "━━━ Footnotes ━━━")
  table.insert(content, "")
  
  for _, id in ipairs(footnote_ids) do
    local footnote = state.footnotes[id]
    local ref_count = #footnote.references
    local ref_text = ref_count > 0 and string.format(" (%d ref%s)", ref_count, ref_count > 1 and "s" or "") or ""
    
    table.insert(content, string.format("[^%s]%s", id, ref_text))
    
    -- Wrap content if it's too long
    local display_content = footnote.content
    if #display_content > config.sidebar_width - 4 then
      display_content = display_content:sub(1, config.sidebar_width - 7) .. "..."
    end
    
    table.insert(content, "  " .. display_content)
    table.insert(content, "")
  end
  
  if #footnote_ids == 0 then
    table.insert(content, "No footnotes found")
  end
  
  vim.api.nvim_buf_set_lines(state.sidebar_buf, 0, -1, false, content)
  
  -- Apply highlighting
  vim.api.nvim_buf_clear_namespace(state.sidebar_buf, -1, 0, -1)
  
  local line_idx = 2 -- Start after header
  for _, id in ipairs(footnote_ids) do
    if line_idx < #content then
      vim.api.nvim_buf_add_highlight(state.sidebar_buf, -1, config.highlight_groups.footnote_id, line_idx, 0, #id + 4)
      line_idx = line_idx + 3 -- Skip id, content, and empty line
    end
  end
end

local function get_footnote_at_cursor()
  local cursor = vim.api.nvim_win_get_cursor(state.sidebar_win)
  local line = cursor[1]
  local content = vim.api.nvim_buf_get_lines(state.sidebar_buf, line - 1, line, false)[1]
  
  if not content then return nil end
  
  local id = content:match("^%[%^([^%]]+)%]")
  return id and state.footnotes[id] or nil
end

local function jump_to_footnote(footnote)
  if not footnote then return end
  
  local source_win = nil
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == state.source_buf then
      source_win = win
      break
    end
  end
  
  if source_win then
    vim.api.nvim_set_current_win(source_win)
    vim.api.nvim_win_set_cursor(source_win, {footnote.line, 0})
    vim.cmd("normal! zz")
  end
end

local function start_edit_mode(footnote)
  if state.is_editing then return end
  
  state.is_editing = true
  state.current_footnote = footnote
  
  -- Create edit buffer
  state.edit_buf = create_buffer("footnote_edit", {
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    modifiable = true,
  })
  
  -- Set initial content
  local content = {
    string.format("Editing footnote: [^%s]", footnote.id),
    "",
    footnote.content
  }
  vim.api.nvim_buf_set_lines(state.edit_buf, 0, -1, false, content)
  
  -- Position cursor on content line
  vim.api.nvim_buf_set_option(state.edit_buf, 'filetype', 'markdown')
  
  -- Create edit window (split the sidebar)
  local sidebar_height = vim.api.nvim_win_get_height(state.sidebar_win)
  local edit_height = math.min(10, math.floor(sidebar_height * 0.4))
  
  vim.api.nvim_win_set_height(state.sidebar_win, sidebar_height - edit_height - 1)
  
  local sidebar_config = vim.api.nvim_win_get_config(state.sidebar_win)
  local edit_config = {
    relative = "editor",
    row = sidebar_config.row + sidebar_height - edit_height,
    col = sidebar_config.col,
    width = config.sidebar_width,
    height = edit_height,
    style = "minimal",
    border = "single",
    title = " Edit Footnote ",
    title_pos = "center",
  }
  
  state.edit_win = create_window(state.edit_buf, edit_config)
  vim.api.nvim_set_current_win(state.edit_win)
  vim.api.nvim_win_set_cursor(state.edit_win, {3, #footnote.content})
  
  -- Set up edit mode keymaps
  local edit_opts = { buffer = state.edit_buf, noremap = true, silent = true }
  vim.keymap.set('n', config.keymaps.save_and_close, function() save_and_close_edit() end, edit_opts)
  vim.keymap.set('n', config.keymaps.cancel_edit, function() cancel_edit() end, edit_opts)
  vim.keymap.set('i', '<C-s>', function() save_and_close_edit() end, edit_opts)
  vim.keymap.set('i', '<Esc>', function() cancel_edit() end, edit_opts)
  
  vim.cmd("startinsert")
end

function save_and_close_edit()
  if not state.is_editing or not state.current_footnote then return end
  
  local lines = vim.api.nvim_buf_get_lines(state.edit_buf, 0, -1, false)
  local new_content = table.concat(lines, "\n", 3) -- Skip header lines
  
  -- Update the source buffer
  local source_lines = vim.api.nvim_buf_get_lines(state.source_buf, 0, -1, false)
  local footnote_line = state.current_footnote.line
  
  if footnote_line <= #source_lines then
    local new_line = string.format("[^%s]: %s", state.current_footnote.id, new_content)
    vim.api.nvim_buf_set_lines(state.source_buf, footnote_line - 1, footnote_line, false, {new_line})
  end
  
  -- Cleanup edit mode
  close_edit_mode()
  
  -- Refresh footnotes and sidebar
  state.footnotes = get_footnotes_from_buffer(state.source_buf)
  update_sidebar_content()
end

function cancel_edit()
  close_edit_mode()
end

function close_edit_mode()
  if state.edit_win then
    close_window(state.edit_win)
    state.edit_win = nil
  end
  
  if state.edit_buf and vim.api.nvim_buf_is_valid(state.edit_buf) then
    vim.api.nvim_buf_delete(state.edit_buf, {force = true})
    state.edit_buf = nil
  end
  
  -- Restore sidebar height
  if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    vim.api.nvim_win_set_height(state.sidebar_win, vim.api.nvim_get_option("lines") - 5)
  end
  
  state.is_editing = false
  state.current_footnote = nil
end

local function create_sidebar()
  if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    return -- Sidebar already exists
  end
  
  -- Create sidebar buffer
  state.sidebar_buf = create_buffer("footnotes_sidebar", {
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    modifiable = false,
  })
  
  -- Calculate sidebar position
  local editor_width = vim.api.nvim_get_option("columns")
  local sidebar_col = config.sidebar_position == 'right' and editor_width - config.sidebar_width or 0
  
  -- Create sidebar window
  local win_config = {
    relative = "editor",
    row = 0,
    col = sidebar_col,
    width = config.sidebar_width,
    height = vim.api.nvim_get_option("lines") - 5,
    style = "minimal",
    border = "single",
    title = " Footnotes ",
    title_pos = "center",
  }
  
  state.sidebar_win = create_window(state.sidebar_buf, win_config)
  
  -- Set up sidebar keymaps
  local sidebar_opts = { buffer = state.sidebar_buf, noremap = true, silent = true }
  vim.keymap.set('n', config.keymaps.edit_footnote, function()
    local footnote = get_footnote_at_cursor()
    if footnote then
      start_edit_mode(footnote)
    end
  end, sidebar_opts)
  
  vim.keymap.set('n', config.keymaps.jump_to_reference, function()
    local footnote = get_footnote_at_cursor()
    if footnote then
      jump_to_footnote(footnote)
    end
  end, sidebar_opts)
  
  vim.keymap.set('n', 'q', function() M.close_sidebar() end, sidebar_opts)
  vim.keymap.set('n', '<C-c>', function() M.close_sidebar() end, sidebar_opts)
end

function M.open_sidebar()
  state.source_buf = vim.api.nvim_get_current_buf()
  
  -- Only work with markdown files
  if vim.bo.filetype ~= "markdown" then
    vim.notify("Footnotes sidebar only works with markdown files", vim.log.levels.WARN)
    return
  end
  
  create_sidebar()
  state.footnotes = get_footnotes_from_buffer(state.source_buf)
  update_sidebar_content()
end

function M.close_sidebar()
  if state.is_editing then
    close_edit_mode()
  end
  
  if state.sidebar_win then
    close_window(state.sidebar_win)
    state.sidebar_win = nil
  end
  
  if state.sidebar_buf and vim.api.nvim_buf_is_valid(state.sidebar_buf) then
    vim.api.nvim_buf_delete(state.sidebar_buf, {force = true})
    state.sidebar_buf = nil
  end
end

function M.toggle_sidebar()
  if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    M.close_sidebar()
  else
    M.open_sidebar()
  end
end

function M.refresh()
  if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
    state.footnotes = get_footnotes_from_buffer(state.source_buf)
    update_sidebar_content()
  end
end

function M.setup(user_config)
  config = vim.tbl_deep_extend('force', config, user_config or {})
  
  -- Set up global keymaps
  vim.keymap.set('n', config.keymaps.toggle_sidebar, function() M.toggle_sidebar() end, 
    { desc = "Toggle footnotes sidebar" })
  
  -- Set up autocommands
  local group = vim.api.nvim_create_augroup("FootnotesPreview", { clear = true })
  
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    group = group,
    pattern = "*.md",
    callback = function()
      if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
        vim.defer_fn(function() M.refresh() end, 100)
      end
    end,
  })
  
  if config.auto_close then
    vim.api.nvim_create_autocmd("BufEnter", {
      group = group,
      callback = function()
        if state.sidebar_win and vim.api.nvim_win_is_valid(state.sidebar_win) then
          local current_buf = vim.api.nvim_get_current_buf()
          if current_buf ~= state.source_buf and vim.bo[current_buf].filetype ~= "markdown" then
            M.close_sidebar()
          end
        end
      end,
    })
  end
  
  -- Create user commands
  vim.api.nvim_create_user_command("FootnotesPreview", function() M.toggle_sidebar() end, {})
  vim.api.nvim_create_user_command("FootnotesOpen", function() M.open_sidebar() end, {})
  vim.api.nvim_create_user_command("FootnotesClose", function() M.close_sidebar() end, {})
  vim.api.nvim_create_user_command("FootnotesRefresh", function() M.refresh() end, {})
end

return M
