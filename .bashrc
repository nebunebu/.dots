. "${HOME}/.private"

set -o vi
complete -cf doas

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

WM=$(wmctrl -m | awk 'NR==1 {printf $2}')
[[ ${WM} = "awesome" ]] && setxkbmap -option "caps:swapescape"

export PS1="\[\033[38;5;6m\][\[$(tput sgr0)\]\[$(tput bold)\]\[\033[38;5;7m\]\W\[$(tput sgr0)\]\[\033[38;5;6m\]]\\$\[$(tput sgr0)\]\[\033[38;5;3m\]\$(git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/')\[$(tput sgr0)\] \[$(tput sgr0)\]"
export PATH="${PATH}:${HOME}/.local/bin/:${HOME}/.scripts/:${HOME}/.local/go/bin"
export CDPATH="${HOME}:${HOME}/Books:${HOME}/Courses:${HOME}/Pictures:${HOME}/Tuts:${HOME}/Documets:.."
export GOPATH="${HOME}/.local/go"
export XDG_CONFIG_HOME="${HOME}/.config/"
export XDG_CACHE_HOME="${HOME}/.cache/"
export XDG_DATA_HOME="${HOME}/.local/share"
export EDITOR="nvim"

export NVIM="${XDG_CONFIG_HOME}/nvim/lua/nebu/"


alias ls='ls --color=auto'
alias f='fastfetch'
alias hyprlog='cat /tmp/hypr/$(ls -t /tmp/hypr/ | head -n 2 | tail -n 1)/hyprland.log'
alias mvim='nvim'
alias dirs='dirs -v'


[ -f "/home/nebu/.ghcup/env" ] && source "/home/nebu/.ghcup/env" # ghcup-env

HISTSIZE=-1
HISTFILESIZE=-1
# Remove duplicate entries from .bash_history and perserver order
tac "$HOME/.bash_history" |\
	awk '!visited[$0]++' > tmp &&\
	tac tmp > "${HOME}/.bash_history" &&\
	rm tmp

# add pywal color to terminals
(cat "${XDG_CACHE_HOME}/wal/sequences" &)
# add pywal color to tty
# source "${XDG_CACHE_HOME}/wal/colors-tty.sh"
# print pywal colors when opening terminal
wal --preview | sed '1d'


# alias mvim="NVIM_APPNAME=mvim nvim"
# alias bvim="NVIM_APPNAME=bvim nvim"
#
# function nvims() {
# 	items=("default" "mvim" "bvim")
# 	config=$(printf "%s\n" "${items[@]}" | fzf --prompt=" Neovim Config  " --height=~50% --layout=reverse --border --exit-0)
#
# 	if [[ -z $config ]]; then
# 		echo "Nothing selected"
# 		return 0
# 	elif [[ $config == "default" ]]; then
# 		config=""
# 	fi
#
# 	NVIM_APPNAME=$config nvim $@
# }
#
# # bindkey -s ^a "nvims\n"
#
# export NVM_DIR="$HOME/.config/nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
