#if set -q SSH_CONNECTION
#    set -x TERM xterm
#end


if status is-interactive
    # Commands to run in interactive sessions can go here
    if not set -q FASTFETCH_SKIP_AUTO
        fastfetch
    end
end
