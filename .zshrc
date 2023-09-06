source ~/.oh-my-zshrc

if [ -f ~/.zshrc.local ]; then
    source ~/.zshrc.local
fi

alias ll='ls -la'
alias memo='nvim ~/memo.txt'
