# footnotes-preview.nvim

A simple LazyVim-compatible Neovim plugin to preview and navigate footnotes in Markdown files via a floating sidebar.

## Features

- 📑 Detects lines like `[^1]: Footnote text`
- 🪟 Opens a floating preview sidebar
- ⛳ Jump to footnote definitions
- 🧩 LazyVim-ready

## Installation

With LazyVim:

```lua
{
  "yourgithub/footnotes-preview.nvim",
  config = function()
    require("footnotes-preview").setup()
  end,
  ft = "markdown",
}
```

## Usage

- Run `:FootnotesPreview` or press `<leader>fn` in a Markdown file
- Use `<CR>` to jump to the selected footnote

## License

MIT
