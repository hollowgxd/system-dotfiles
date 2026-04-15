#if set -q SSH_CONNECTION
#    set -x TERM xterm
#end


if status is-interactive
    # Commands to run in interactive sessions can go here
    if not set -q FASTFETCH_SKIP_AUTO
        fastfetch
    end
end
alias happ-reset="pkill -9 -f '/opt/happ/bin/Happ'; pkill -9 -x happ; pkill -9 -f happd; rm -f /tmp/happd.sock /tmp/tcU0WK5PwneH++Y9c0o680J7cW+IVVsFTUXqGYhUOV8= /dev/shm/tcU0WK5PwneH++Y9c0o680J7cW+IVVsFTUXqGYhUOV8="
