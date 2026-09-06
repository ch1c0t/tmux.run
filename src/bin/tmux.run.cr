require "./tmux.run/*"

VERSION = "0.0.0"

case ARGV.size
when 1
  case ARGV[0]
  when "-v", "version", "--version"
    puts VERSION
    exit
  when "-h", "help", "--help"
    print_help
    exit
  end
end

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

output_file = ARGV[0]       # Your fix perfectly resolves string target casting
commands_to_run = ARGV[1..] # Array slice

runner = Runner.new(commands_to_run, output_file)
runner.run!
