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
require "file_utils"
require "memoization"

require "../config"
require "../c"
require "../command_result"
require "../pty_command"
require "../tmux"
require "../runner"

if ARGV.size < 2
  puts "Usage: tmux.run <output_log.yaml> \"command 1\" \"command 2\" ..."
  exit 1
end

commands_to_run = ARGV
runner = Runner.new(commands_to_run)
runner.run!
