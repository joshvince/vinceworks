# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
# ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"
plugins=(git dotenv bundler)

source $ZSH/oh-my-zsh.sh

# User configuration

# Update the screenshots location and a couple of other tweaks
source $HOME/.macosdefaults.sh

# load sensitive credentials from a local file
source $HOME/.credentials

# Load some handy shortcuts
source $HOME/.shortcuts
[[ -f $HOME/.shortcuts.private ]] && source $HOME/.shortcuts.private

# carwow-specific shortcuts
source $HOME/.carwow-shortcuts.sh

PATH="$(brew --prefix)/opt/coreutils/libexec/gnubin:$PATH"
PATH="$(brew --prefix)/opt/findutils/libexec/gnubin:$PATH"
PATH="$(brew --prefix)/opt/gnu-sed/libexec/gnubin:$PATH"
PATH=$PATH:$HOME/projects/carwow/dev-environment/bin


# . /usr/local/opt/asdf/etc/bash_completion.d/asdf.bash
# . /usr/local/opt/asdf/asdf.sh

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

export NODE_OPTIONS="--max-old-space-size=8192"

export PATH=$PATH:~/go/bin

# thefuck shell plugin
eval $(thefuck --alias)

# stop homebrew auto-updating all the time
export HOMEBREW_NO_AUTO_UPDATE=1

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# LLM nonsense
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/homebrew/Caskroom/miniconda/base/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh" ]; then
        . "/opt/homebrew/Caskroom/miniconda/base/etc/profile.d/conda.sh"
    else
        export PATH="/opt/homebrew/Caskroom/miniconda/base/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# PATH_TO_CKPT="~/projects/bfirsh:stable-diffusion/models/ldm/stable-diffusion-v1/model.ckpt"
# ln -s "$PATH_TO_CKPT/sd-v1-4.ckpt" ~/projects/stable-diffusion/models/ldm/stable-diffusion-v1/model.ckpt

# END LLM NONSENSE
export path
export PATH="$HOME/.local/bin:$PATH"

eval "$(rbenv init - zsh)"

# opencode
export PATH=/Users/joshvince/.opencode/bin:$PATH
