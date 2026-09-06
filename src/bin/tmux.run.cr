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
# 1. DATA STRUCTURES
# =============================================================================

struct CommandResult
  include YAML::Serializable

  property command : String
  property stdout : String 
  property stderr : String 
  property exit_code : Int32

  def initialize(@command, @stdout, @stderr, @exit_code)
  end
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
