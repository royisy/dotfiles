set number            " add line numbers
syntax on             " syntax highlighting
set clipboard=unnamed " copy to clipboard
set list              " show invisible chars
set listchars=trail:· " overwrite invisible chars
set mouse=a           " mouse support

set showmatch         " show matching
set ignorecase        " case insensitive
set hlsearch          " highlight search
set incsearch         " incremental search
set wrapscan          " return to beginning

set expandtab         " converts tabs to white space
set tabstop=4         " number of columns occupied by a tab
set softtabstop=4     " see multiple spaces as tabstops so <BS> does the right thing
set autoindent        " indent a new line the same amount as the line just typed
set shiftwidth=4      " width for autoindents

if exists('g:vscode')
    " VSCode extension
else
    call plug#begin()
    Plug 'farmergreg/vim-lastplace'
    call plug#end()
endif

" save file
nnoremap <c-s> :w<cr>

" turn off highlight
nnoremap <esc><esc> :nohlsearch<cr>

" insert blank line
nnoremap <Enter> o<ESC>
nnoremap <S-Enter> O<ESC>

" share clipboard with windows in wsl
if system('uname -a | grep microsoft') != ''
    let g:clipboard = {
        \   'name': 'myClipboard',
        \   'copy': {
        \      '+': 'win32yank.exe -i',
        \      '*': 'win32yank.exe -i',
        \    },
        \   'paste': {
        \      '+': 'win32yank.exe -o',
        \      '*': 'win32yank.exe -o',
        \   },
        \   'cache_enabled': 1,
        \ }
endif
