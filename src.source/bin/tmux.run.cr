require "yaml"
require "process"
require "file_utils"

require "../config"
require "../command_result"
require "../tmux"
require "../runner"

if ARGV.size < 1
  puts "Usage: tmux.run \"command 1\" \"command 2\" ..."
  exit 1
end

commands_to_run = ARGV
runner = Runner.new(commands_to_run)
runner.run!
