require "yaml"
require "process"

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

class TmuxVisualPane
  getter id : String

  def initialize
    @id = `tmux split-window -h -P 'cat; exec bash'`.strip
  end

  def stream_command_mirror(cmd_str : String)
    header = "\n\e[1;34m[Running PTY]: #{cmd_str}\e[0m\n"
    Process.run("tmux", ["send-keys", "-t", @id, header])
  end

  def stream_output(output_text : String)
    Process.run("tmux", ["send-keys", "-t", @id, output_text])
  end

  def alert_failure!
    alert_msg = "\n\e[1;31m[tmux.run] Execution halted inside PTY. Skipped remaining steps.\e[0m\n"
    Process.run("tmux", ["send-keys", "-t", @id, alert_msg])
    Process.run("tmux", ["send-keys", "-t", @id, "C-d"])
  end

  def close!
    Process.run("tmux", ["kill-pane", "-t", @id])
  end
end

# =============================================================================
# 3. RUNNER ENGINE
# =============================================================================

class HighPrecisionRunner
  def initialize(@commands : Array(String), @output_yaml_path : String)
    unless ENV.has_key?("TMUX")
      puts "Error: This program must be run inside an active Tmux session."
      exit 1
    end

    @pane = TmuxVisualPane.new
    @run_id = Process.pid
    @results = [] of CommandResult
    @failed = false

    puts "Allocated Right Visual Tmux Pane: #{@pane.id}"
  end

  def run!
    @commands.each_with_index do |cmd_str, index|
      puts "Processing inside PTY #{index + 1}/#{@commands.size}: '#{cmd_str}'"
      
      @pane.stream_command_mirror(cmd_str)

      cmd = RealPtyCommand.new(cmd_str, index, @run_id)
      raw_pty_output, exit_code = cmd.execute_inside_pty

      unless raw_pty_output.empty?
        @pane.stream_output(raw_pty_output)
      end

      @results << CommandResult.new(
        command: cmd_str,
        stdout: raw_pty_output,
        stderr: "", 
        exit_code: exit_code
      )

      if exit_code != 0
        puts "\n[!] PTY Command broke with code #{exit_code}. Terminating automation."
        @pane.alert_failure!
        @failed = true
        break
      end
    end

    finalize_session
  end

  private def finalize_session
    unless @failed
      Process.run("tmux", ["send-keys", "-t", @pane.id, "C-d"])
      @pane.close!
    end

    File.write(@output_yaml_path, @results.to_yaml)
    puts "High-precision PTY serialization complete: #{@output_yaml_path}"
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

runner = HighPrecisionRunner.new(commands_to_run, output_file)
runner.run!
