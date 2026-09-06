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
# 2. THE REAL PTY ALLOCATION ENGINE
# =============================================================================

class RealPtyCommand
  getter raw_string : String
  getter status_path : String

  def initialize(@raw_string, index : Int32, run_id : Int64)
    @status_path = "/tmp/pty_status_#{run_id}_#{index}.txt"
  end

  def execute_inside_pty : Tuple(String, Int32)
    if C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
      raise "Error: OS failed to allocate high-precision PTY descriptors."
    end

    pid = C.fork
    if pid < 0
      raise "Error: OS process fork failed."
    elsif pid == 0
      C.login_tty(slave_fd)
      ENV["TERM"] = "xterm-256color"
      Process.exec("/bin/sh", ["-c", "( #{@raw_string} ); echo $? > #{@status_path}"])
      C._exit(1)
    else
      IO::FileDescriptor.new(slave_fd, close_on_finalize: true).close

      master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
      buffer = IO::Memory.new

      begin
        io_buffer = Bytes.new(4096)
        while (bytes_read = master_io.read(io_buffer)) > 0
          buffer.write(io_buffer[0, bytes_read])
        end
      rescue IO::Error
        # EIO error caught when slave descriptor drops
      end

      while !File.exists?(@status_path)
        sleep(50.milliseconds)
      end

      exit_code = File.read(@status_path).strip.to_i
      File.delete(@status_path) if File.exists?(@status_path)

      {buffer.to_s, exit_code}
    end
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
