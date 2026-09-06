require "yaml"
require "process"

require "../c"
require "../command_result"
require "../pty_command"
require "../tmux"
require "../runner"

if ARGV.size < 2
  puts "Usage: tmux.run <output_log.yaml> \"command 1\" \"command 2\" ..."
  exit 1
end

output_file = ARGV[0]
commands_to_run = ARGV[1..]

runner = Runner.new(commands_to_run, output_file)
runner.run!
