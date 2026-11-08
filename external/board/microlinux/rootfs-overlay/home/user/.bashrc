[ -z "$PS1" ] && return
PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
HISTSIZE=2000
HISTCONTROL=ignoredups
alias ls='ls --color=auto'
alias ll='ls -lh'
alias grep='grep --color=auto'
