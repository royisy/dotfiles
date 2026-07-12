vim.opt.number = true -- Show line numbers
vim.cmd.syntax("on") -- Enable syntax highlighting
pcall(vim.cmd.colorscheme, "habamax") -- Explicit colorscheme: portable colors across nvim versions (0.10+ default is muted)
vim.opt.clipboard = "unnamed" -- Use the system clipboard
vim.opt.list = true -- Show invisible characters
vim.opt.listchars = { tab = ">-", trail = "·" } -- Define invisible characters
vim.opt.mouse = "a" -- Enable mouse support
vim.opt.termguicolors = true -- 24-bit truecolor (needs tmux RGB passthrough inside tmux)

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
  vim.opt.spellcapcheck = "" -- Don't flag a lowercase sentence-start word (false underline on terms at line/bullet starts)
  vim.cmd("highlight SpellBad cterm=underline ctermbg=NONE")
  vim.cmd("highlight SpellCap ctermbg=NONE")
end

-- Use Tree-sitter highlighting for Markdown (bundled markdown parser on 0.10+).
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    pcall(vim.treesitter.start)
    -- Don't render ~text~ with a strike-through (Tree-sitter markdown highlight).
    vim.api.nvim_set_hl(0, "@markup.strikethrough", {})
  end,
})

-- Common key mappings.
vim.keymap.set("n", "<C-s>", "<cmd>write<cr>")
vim.keymap.set("n", "<Esc><Esc>", "<cmd>nohlsearch<cr>")
vim.keymap.set("n", "<CR>", "o<Esc>")
vim.keymap.set("n", "<leader>w", "<cmd>set wrap!<cr>") -- Toggle line wrapping (default on)

-- Persist the cursor position independently of ShaDa marks.
vim.opt.viewoptions = { "cursor" }
vim.cmd([[
  augroup cursor_view
    autocmd!
    autocmd BufWinLeave * if &buftype ==# '' && expand('%') !=# '' | mkview! | endif
    autocmd BufWinEnter * if &buftype ==# '' && expand('%') !=# '' | silent! loadview | endif
    autocmd VimEnter * if &buftype ==# '' && expand('%') !=# '' | silent! loadview | endif
  augroup END
]])

local has_fzf_lua, fzf_lua = pcall(require, "fzf-lua")
if has_fzf_lua then
  fzf_lua.setup({})
  vim.keymap.set("n", "<C-p>", fzf_lua.files)
  vim.keymap.set("n", "<C-g>", fzf_lua.live_grep)
  vim.keymap.set("n", "<leader>b", fzf_lua.buffers)
  vim.keymap.set("n", "<leader>h", fzf_lua.help_tags)
end

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
