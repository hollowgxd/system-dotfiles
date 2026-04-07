#
# ~/.bashrc
#

[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
#PS1='[\u@\h \W]\$ '
[[ "$TERM" == "xterm-kitty" ]] && alias ssh="TERM=xterm-256color ssh"
. "$HOME/.cargo/env"
