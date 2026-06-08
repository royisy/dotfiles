vim.opt.number = true -- Show line numbers
vim.cmd.syntax("on") -- Enable syntax highlighting
vim.opt.clipboard = "unnamed" -- Use the system clipboard
vim.opt.list = true -- Show invisible characters
vim.opt.listchars = { tab = ">-", trail = "." } -- Define invisible characters
vim.opt.mouse = "a" -- Enable mouse support

vim.opt.showmatch = true -- Highlight matching brackets
vim.opt.ignorecase = true -- Ignore case when searching
vim.opt.hlsearch = true -- Highlight search results
vim.opt.incsearch = true -- Search while typing
vim.opt.wrapscan = true -- Wrap searches around the file

vim.opt.expandtab = true -- Insert spaces instead of tabs
vim.opt.tabstop = 4 -- Display tabs as four spaces
vim.opt.softtabstop = 4 -- Use four spaces when editing tabs
vim.opt.autoindent = true -- Copy indentation from the current line
vim.opt.shiftwidth = 4 -- Indent by four spaces

-- Enable spell checking outside VSCode.
if not vim.g.vscode then
  vim.opt.spell = true
  vim.opt.spelllang = { "en", "cjk" } -- Skip CJK characters so Japanese is not underlined
  vim.cmd("highlight SpellBad cterm=underline ctermbg=NONE")
  vim.cmd("highlight SpellCap ctermbg=NONE")
end

-- Common key mappings.
vim.keymap.set("n", "<C-s>", "<cmd>write<cr>")
vim.keymap.set("n", "<Esc><Esc>", "<cmd>nohlsearch<cr>")
vim.keymap.set("n", "<CR>", "o<Esc>")

-- Restore the last cursor position when reopening a file.
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(args)
    local position = vim.api.nvim_buf_get_mark(args.buf, '"')
    local line_count = vim.api.nvim_buf_line_count(args.buf)

    if position[1] > 1 and position[1] <= line_count then
      pcall(vim.api.nvim_win_set_cursor, 0, position)
    end
  end,
})

-- Share the Windows clipboard when win32yank is available in WSL.
if vim.fn.has("wsl") == 1 and vim.fn.executable("win32yank.exe") == 1 then
  vim.g.clipboard = {
    name = "win32yank",
    copy = {
      ["+"] = { "win32yank.exe", "-i" },
      ["*"] = { "win32yank.exe", "-i" },
    },
    paste = {
      ["+"] = { "win32yank.exe", "-o", "--lf" },
      ["*"] = { "win32yank.exe", "-o", "--lf" },
    },
    cache_enabled = 1,
  }
end
