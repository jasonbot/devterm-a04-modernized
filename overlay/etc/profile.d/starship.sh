# Use Starship as the default prompt.  The system config is also installed
# under /etc/skel and the image's existing users, so this works without
# STARSHIP_CONFIG for normal users.
if [ -n "${BASH_VERSION-}" ] && command -v starship >/dev/null 2>&1 && \
   [ -z "${STARSHIP_SHELL-}" ]; then
    eval "$(starship init bash)"
fi
