#if set -q SSH_CONNECTION
#    set -x TERM xterm
#end


if status is-interactive
    # Commands to run in interactive sessions can go here
	fastfetch
end
