#
# .zshrc is sourced in interactive shells.
# It should contain commands to set up aliases,
# functions, options, key bindings, etc.
#

# ---------------------------------------------------------------------------
# History
# ---------------------------------------------------------------------------
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt EXTENDED_HISTORY          # timestamp + duration in history
setopt INC_APPEND_HISTORY        # append incrementally, not on exit
setopt SHARE_HISTORY             # share history between sessions
setopt HIST_IGNORE_ALL_DUPS      # drop older duplicates
setopt HIST_IGNORE_SPACE         # ignore commands starting with a space
setopt HIST_REDUCE_BLANKS        # strip superfluous blanks
setopt HIST_VERIFY               # show substitutions before running

# ---------------------------------------------------------------------------
# Shell behaviour
# ---------------------------------------------------------------------------
setopt AUTO_CD                  # cd by typing a directory name
setopt AUTO_PUSHD               # cd pushes onto the directory stack
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt COMPLETE_IN_WORD         # complete in the middle of a word
setopt INTERACTIVE_COMMENTS     # allow # comments on the command line
setopt NO_BEEP                  # never beep
setopt NO_FLOW_CONTROL
setopt PROMPT_SUBST             # expand prompt substitutions

# ---------------------------------------------------------------------------
# Completion
# ---------------------------------------------------------------------------
autoload -Uz compinit
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
mkdir -p "$cache_dir"

if [[ -f "$cache_dir/zcompdump" && $cache_dir/zcompdump -nt /usr/bin/zsh ]]; then
  compinit -C -d "$cache_dir/zcompdump"
else
  compinit -d "$cache_dir/zcompdump"
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' group-name ''
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$cache_dir"
zstyle ':completion:*' completer _complete _match _approximate
zstyle ':completion:*:approximate:*' max-errors 2 numeric
zstyle ':completion:*:sudo:*' command-path /usr/local/sbin /usr/local/bin \
                                              /usr/sbin /usr/bin /sbin /bin
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' squeeze-slashes true

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
autoload -Uz colors && colors

if [[ -t 1 ]]; then
  export LESS='-R'
  export LESS_TERMCAP_mb=$'\e[1;31m'
  export LESS_TERMCAP_md=$'\e[1;36m'
  export LESS_TERMCAP_me=$'\e[0m'
  export LESS_TERMCAP_se=$'\e[0m'
  export LESS_TERMCAP_so=$'\e[1;44;33m'
  export LESS_TERMCAP_ue=$'\e[0m'
  export LESS_TERMCAP_us=$'\e[1;32m'
fi

if command -v dircolors >/dev/null 2>&1; then
  eval "$(dircolors -b 2>/dev/null)"
fi

# ---------------------------------------------------------------------------
# Plugins (Fedora packaged)
# ---------------------------------------------------------------------------
[[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

[[ -r /usr/share/fzf/shell/key-bindings.zsh ]] && \
  source /usr/share/fzf/shell/key-bindings.zsh

# syntax-highlighting must be sourced last
[[ -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border \
  --color=bg+:#3c3836,bg:#282828,spinner:#fb4934,hl:#928374 \
  --color=fg:#ebdbb2,header:#928374,info:#8ec07c,pointer:#fb4934 \
  --color=marker:#b8bb26,fg+:#ebdbb2,prompt:#fabd2f,hl+:#fabd2f \
  --color=selected-bg:#504945"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="--preview 'bat --style=numbers --color=always --line-range :200 {}'"
export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
export FZF_ALT_C_OPTS="--preview 'eza --tree --level=2 --icons --color=always {}'"

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------
autoload -Uz vcs_info
precmd_functions+=(vcs_info)
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr   '%F{green}●%f'
zstyle ':vcs_info:git:*' unstagedstr '%F{yellow}●%f'
zstyle ':vcs_info:git:*' formats       ' %F{blue}%b%f%c%u'
zstyle ':vcs_info:git:*' actionformats ' %F{blue}%b%f%c%u %F{red}(%a)%f'

PROMPT='%F{green}%n@%h%f %F{cyan}%~%f${vcs_info_msg_0_}
%(?..%F{red}%?%f )%F{magenta}❯%f '

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------
# ls / navigation
alias ls='eza --icons --group-directories-first'
alias ll='eza -lh --icons --group-directories-first --git'
alias la='eza -lah --icons --group-directories-first --git'
alias lt='eza --tree --level=2 --icons'
alias l='ls'
alias cat='bat --paging=never'
alias grep='grep --color=auto'
alias cd..='cd ..'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# git
alias g='git'
alias gs='git status -sb'
alias gd='git diff'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gco='git checkout'
alias gb='git branch'
alias gl='git log --oneline --graph --decorate -20'
alias gll='git log --oneline --graph --decorate --all'
alias gp='git push'
alias gpl='git pull'
alias gr='git remote -v'
alias gst='git stash'

# misc
alias q='exit'
alias c='clear'
alias reload='source ~/.zshrc'
alias path='echo -e ${PATH//:/\\n}'
alias ports='ss -tulpn'
alias df='df -h'
alias free='free -h'
alias mkdir='mkdir -p'
alias please='sudo $(fc -ln -1)'

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------
mkcd() { mkdir -p "$1" && cd "$1"; }

extract() {
  if [[ -f "$1" ]]; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1" ;;
      *.tar.gz)    tar xzf "$1" ;;
      *.tar.xz)    tar xJf "$1" ;;
      *.tar.zst)   tar --zstd -xf "$1" ;;
      *.bz2)       bunzip2 "$1" ;;
      *.rar)       unrar x "$1" ;;
      *.gz)        gunzip "$1" ;;
      *.tar)       tar xf "$1" ;;
      *.tbz2)      tar xjf "$1" ;;
      *.tgz)       tar xzf "$1" ;;
      *.zip)       unzip "$1" ;;
      *.Z)         uncompress "$1" ;;
      *.7z)        7z x "$1" ;;
      *)           echo "extract: '$1' - unknown archive format" ;;
    esac
  else
    echo "extract: '$1' - not a valid file"
  fi
}

# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
[[ -o interactive ]] && command -v fastfetch >/dev/null 2>&1 && fastfetch
