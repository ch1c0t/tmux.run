require "yaml"
require "process"

require "../command_result"
require "../pty_command"
require "../tmux"
require "../runner"

lib C
  fun openpty(amaster : Int32*, aslave : Int32*, name : UInt8*, termp : Void*, winp : Void*) : Int32
  fun login_tty(fd : Int32) : Int32
  fun fork : Int32
  fun _exit(status : Int32) : NoReturn
end

# =============================================================================
# 4. ENTRY POINT
# =============================================================================
if ARGV.size < 2
  puts "Usage: tmux.run <output_log.yaml> \"command 1\" \"command 2\" ..."
  exit 1
end

output_file = ARGV[0]       # Your fix perfectly resolves string target casting
commands_to_run = ARGV[1..] # Array slice

runner = Runner.new(commands_to_run, output_file)
runner.run!
