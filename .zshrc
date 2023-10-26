. "${HOME}/.config/shell/profile"

bindkey -v

export XDG_CACHE_HOME="${HOME}/.cache/"
export XDG_DATA_HOME="${HOME}/.local/share"
export EDITOR="nvim"
export GOPATH="${HOME}/.local/go/"
export CLIPBOARD="wl-clipboard"
export ZSH_SYSTEM_CLIPBOARD_METHOD="wlc"
export PATH="${PATH}:${HOME}/.local/bin/:${HOME}/.scripts/:${HOME}/.local/go/bin:${HOME}/.cargo/bin:${HOME}/.ghcup/bin:${HOME}/hls/2.4.0.0/lib/haskell-language-server-2.4.0.0/bin/haskell-language-server-wrapper"
export TUIR_EDITOR="nvim"
export TUIR_BROWSER="chromium"
export TUIR_URLVIEWER="urlview"
export GNUPGHOME="${HOME}/.gnupg"

export HISTFILE=~/.histfile
export HISTSIZE=100
export SAVEHIST=5000


setopt SHARE_HISTORY
setopt APPEND_HISTORY

unsetopt beep

eval "$(oh-my-posh init zsh --config ~/.config/shell/themes/jellyfish.omp.json)"

zstyle :compinstall filename '/home/nebu/.zshrc'

autoload -Uz compinit
compinit

autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit


alias ls="ls --color=auto"
# alias cat="bat"
alias grep="grep --color=auto"
alias ip="ip --color=auto"
alias icat="kitty icat"

source "/usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"
source "/usr/share/zsh/plugins/zsh-vi-mode-0.10.0/zsh-vi-mode.plugin.zsh"
source "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
source "/usr/share/zsh/plugins/zsh-system-clipboard/zsh-system-clipboard.zsh"
# add colored man pages
alias dce=discord-chat-exporter-cli

(cat ~/.cache/wal/sequences &)

zvm_vi_yank () {
	zvm_yank
	printf %s "${CUTBUFFER}" |  wl-copy -n
	zvm_exit_visual_mode
}

my_zvm_vi_delete() {
  zvm_vi_delete
  echo -en "${CUTBUFFER}" | wl-copy -n
}

my_zvm_vi_change() {
  zvm_vi_change
  echo -en "${CUTBUFFER}" | wl-copy -n
}

my_zvm_vi_change_eol() {
  zvm_vi_change_eol
  echo -en "${CUTBUFFER}" | wl-copy -n
}

my_zvm_vi_put_after() {
  CUTBUFFER=$(wl-paste)
  zvm_vi_put_after
  zvm_highlight clear # zvm_vi_put_after introduces weird highlighting for me
}

my_zvm_vi_put_before() {
  CUTBUFFER=$(wl-paste)
  zvm_vi_put_before
  zvm_highlight clear # zvm_vi_put_before introduces weird highlighting for me
}

zvm_after_lazy_keybindings() {
  zvm_define_widget my_zvm_vi_yank
  zvm_define_widget my_zvm_vi_delete
  zvm_define_widget my_zvm_vi_change
  zvm_define_widget my_zvm_vi_change_eol
  zvm_define_widget my_zvm_vi_put_after
  zvm_define_widget my_zvm_vi_put_before

  zvm_bindkey visual 'y' my_zvm_vi_yank
  zvm_bindkey visual 'd' my_zvm_vi_delete
  zvm_bindkey visual 'x' my_zvm_vi_delete
  zvm_bindkey vicmd  'C' my_zvm_vi_change_eol
  zvm_bindkey visual 'c' my_zvm_vi_change
  zvm_bindkey vicmd  'p' my_zvm_vi_put_after
  zvm_bindkey vicmd  'P' my_zvm_vi_put_before
}

tmux-window-name() {
	($TMUX_PLUGIN_MANAGER_PATH/tmux-window-name/scripts/rename_session_windows.py &)
}

add-zsh-hook chpwd tmux-window-name

# alias nvim-astro="NVIM_APPNAME=AstroNvim nvim"

function nvims() {
  items=("default" "kickstart" "LazyVim" "NvChad" "AstroNvim")
  config=$(printf "%s\n" "${items[@]}" | fzf --prompt=" Neovim Config  " --height=~50% --layout=reverse --border --exit-0)
  if [[ -z $config ]]; then
    echo "Nothing selected"
    return 0
  elif [[ $config == "default" ]]; then
    config=""
  fi
  NVIM_APPNAME=$config nvim $@
}

bindkey -s ^a "nvims\n"

[ -f "/home/nebu/.ghcup/env" ] && source "/home/nebu/.ghcup/env" # ghcup-env
