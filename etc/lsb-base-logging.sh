# Default init script logging functions suitable for Ubuntu.
# See /lib/lsb/init-functions for usage help.
LOG_DAEMON_MSG=""

log_use_plymouth () {
    if [ "${loop:-n}" = y ]; then
        return 1
    fi
    plymouth --ping >/dev/null 2>&1
}

log_success_msg () {
    echo " * $@"
}

log_failure_msg () {
    if log_use_fancy_output; then
        RED=`$TPUT setaf 1`
        NORMAL=`$TPUT op`
        echo " $RED*$NORMAL $@"
    else
        echo " * $@"
    fi
}

log_warning_msg () {
    if log_use_fancy_output; then
        YELLOW=`$TPUT setaf 3`
        NORMAL=`$TPUT op`
        echo " $YELLOW*$NORMAL $@"
    else
        echo " * $@"
    fi
}

log_begin_msg () {
    log_daemon_msg "$1"
}

log_daemon_msg () {
    if [ -z "$1" ]; then
        return 1
    fi

    if log_use_fancy_output && $TPUT xenl >/dev/null 2>&1; then
        COLS=`$TPUT cols`
        if [ "$COLS" ] && [ "$COLS" -gt 6 ]; then
            COL=`$EXPR $COLS - 7`
        else
            COLS=80
            COL=73
        fi

        if log_use_plymouth; then
            # If plymouth is running, don't output anything at this time
            # to avoid buffering problems (LP: #752393)
            if [ -z "$LOG_DAEMON_MSG" ]; then
                LOG_DAEMON_MSG=$*
                return
            fi
        fi

        # We leave the cursor `hanging' about-to-wrap (see terminfo(5)
        # xenl, which is approximately right). That way if the script
        # prints anything then we will be on the next line and not
        # overwrite part of the message.

        # Previous versions of this code attempted to colour-code the
        # asterisk but this can't be done reliably because in practice
        # init scripts sometimes print messages even when they succeed
        # and we won't be able to reliably know where the colourful
        # asterisk ought to go.

        printf " * $*       "
        # Enough trailing spaces for ` [fail]' to fit in; if the message
        # is too long it wraps here rather than later, which is what we
        # want.
        $TPUT hpa `$EXPR $COLS - 1`
        printf ' '
    else
        echo " * $@"
        COL=
    fi
}

log_progress_msg () {
    :
}

log_end_msg () {
    if [ -z "$1" ]; then
        return 1
    fi

    if [ "$COL" ] && [ -x "$TPUT" ]; then
        # If plymouth is running, print previously stored output
        # to avoid buffering problems (LP: #752393)
        if log_use_plymouth; then
            if [ -n "$LOG_DAEMON_MSG" ]; then
                log_daemon_msg $LOG_DAEMON_MSG
                LOG_DAEMON_MSG=""
            fi
        fi

        printf "\r"
        $TPUT hpa $COL
        if [ "$1" -eq 0 ]; then
            echo "[ OK ]"
        else
            printf '['
            $TPUT setaf 1 # red
            printf fail
            $TPUT op # normal
            echo ']'
        fi
    else
        if [ "$1" -eq 0 ]; then
            echo "   ...done."
        else
            echo "   ...fail!"
        fi
    fi
    return $1
}

log_action_msg () {
    echo " * $@"
}

log_action_begin_msg () {
    log_daemon_msg "$@..."
}

log_action_cont_msg () {
    log_daemon_msg "$@..."
}

log_action_end_msg () {
    # In the future this may do something with $2 as well.
    log_end_msg "$1" || true
}
