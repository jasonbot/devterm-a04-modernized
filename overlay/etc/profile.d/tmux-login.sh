# Attach interactive login shells to a persistent tmux session named "login".
if [ -z "${TMUX-}" ] && [ -n "${PS1-}" ] && [ -t 0 ] && \
   command -v tmux >/dev/null 2>&1; then
    exec tmux new-session -A -s login
fi
