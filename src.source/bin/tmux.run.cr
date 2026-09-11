require "yaml"
require "process"
require "file_utils"
require "memoization"

require "../config"
require "../c"
require "../yaml_block_string_converter"
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
