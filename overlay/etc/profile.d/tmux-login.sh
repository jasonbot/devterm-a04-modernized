# Attach interactive login shells to a persistent tmux session named "login".
# SSH logins are left alone: a remote shell should be a plain shell, and tmux
# inside another tmux (or inside an ssh command) is surprising.  Attach by
# hand with: tmux new -A -s login
if [ -z "${TMUX-}" ] && [ -z "${SSH_CONNECTION-}" ] && [ -n "${PS1-}" ] && \
   [ -t 0 ] && command -v tmux >/dev/null 2>&1; then
    exec tmux new-session -A -s login
fi
