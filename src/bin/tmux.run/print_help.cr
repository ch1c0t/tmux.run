HELP_MESSAGE = <<-S
tmux.run is a CLI to run a list of commands sequentially, while also streaming
their output to a Tmux pane and saving it to /tmp/$USER/tmux.run/ in both
human- and machine-readable forms.

For example:

    tmux.run "ls --color=always -la" "npm --version" "echo 'Success'"

would run three commands, one by one.

If any of the commands fails(returns a non-zero exit code), the execution stops
and the pane stays open for inspection and debugging, and to indicate that
something went wrong. If all commands succeed, the pane closes.

By default, the focus stays in the active pane(to not interfere with what you
do in it). To auto-move to the debugging pane, pass TMUXRUN_CHANGE_FOCUS=true:

    TMUXRUN_CHANGE_FOCUS=true tmux.run "ls --color=always -la" "npm --version" "false" "echo 'Success'"
S

def print_help
  puts HELP_MESSAGE
end
