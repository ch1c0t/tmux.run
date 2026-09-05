require "yaml"
require "process"

# =============================================================================
# 1. DATA STRUCTURES
# =============================================================================

# Represents the final serialized log format for YAML output
struct CommandResult
  include YAML::Serializable

  property command : String
  property stdin : String
  property stdout : String
  property stderr : String
  property exit_code : Int32

  def initialize(@command, @stdin, @stdout, @stderr, @exit_code)
  end
end

# =============================================================================
# 2. DOMAIN CLASSES
# =============================================================================

# Encapsulates a single command text and its unique temp-file tracking lifecycle
class LoggedCommand
  getter raw_string : String
  getter stdout_path : String
  getter stderr_path : String
  getter status_path : String

  def initialize(@raw_string, index : Int32, run_id : Int64)
    @stdout_path = "/tmp/tmux_run_out_#{run_id}_#{index}.txt"
    @stderr_path = "/tmp/tmux_run_err_#{run_id}_#{index}.txt"
    @status_path = "/tmp/tmux_run_status_#{run_id}_#{index}.txt"
  end

  # Wraps the raw shell command to route standard streams and store the exit code
  def wrapped_payload : String
    "( #{@raw_string} ) > #{@stdout_path} 2> #{@stderr_path}; echo $? > #{@status_path}"
  end

  # Blocks execution cleanly until the external shell finishes and writes its status
  def wait_for_completion
    while !File.exists?(@status_path)
      sleep 100.milliseconds
    end
    sleep 100.milliseconds # Small safety delay to let the OS finalize file flush operations
  end

  # Captures the raw file contents safely, handling missing files gracefully
  def read_outputs : Tuple(String, String, Int32)
    stdout_content = File.exists?(@stdout_path) ? File.read(@stdout_path) : ""
    stderr_content = File.exists?(@stderr_path) ? File.read(@stderr_path) : ""
    exit_code = File.exists?(@status_path) ? File.read(@status_path).strip.to_i : -1
    
    {stdout_content, stderr_content, exit_code}
  end

  # Self-contained cleanup logic to purge the disk footprint
  def cleanup!
    File.delete(@stdout_path) if File.exists?(@stdout_path)
    File.delete(@stderr_path) if File.exists?(@stderr_path)
    File.delete(@status_path) if File.exists?(@status_path)
  end
end

# Abstracts the right-hand Tmux pane layout, lifecycle, and signaling
class TmuxPane
  getter id : String

  def initialize
    # -h creates a vertical split (placing the new pane on the right)
    # -P forces tmux to instantly print only the unique Pane ID string back to us
    @id = `tmux split-window -h -P 'bash'`.strip
  end

  # Passes raw string payloads straight to the target pane's PTY input buffer
  def send_keys(payload : String)
    Process.run("tmux", ["send-keys", "-t", @id, payload, "Enter"])
  end

  # Displays a bright Red warning block directly inside the target interactive pane
  def alert_failure!
    alert_msg = "echo -e '\\n\\e[1;31m[tmux.run] Execution halted here. Remaining commands skipped.\\e[0m\\n'"
    send_keys(alert_msg)
  end

  # Safely tears down and closes the pane window
  def close!
    Process.run("tmux", ["kill-pane", "-t", @id])
  end
end

# =============================================================================
# 3. ORCHESTRATION ENGINE
# =============================================================================

# Coordinates the execution lifecycle across the Pane and the Commands list
class ExecutionRunner
  def initialize(@commands : Array(String), @output_yaml_path : String)
    # Ensure this is executing from inside an active tmux workspace
    unless ENV.has_key?("TMUX")
      puts "Error: This program must be run inside an active Tmux session."
      exit 1
    end

    @pane = TmuxPane.new
    @run_id = Process.pid
    @results = [] of CommandResult
    @failed = false
    
    puts "Opened right half execution pane: #{@pane.id}"
  end

  def run!
    @commands.each_with_index do |cmd_str, index|
      puts "Running command #{index + 1}/#{@commands.size}: '#{cmd_str}'"
      
      # Setup tracking structure
      cmd = LoggedCommand.new(cmd_str, index, @run_id)
      
      # Feed the execution payload to the right pane
      @pane.send_keys(cmd.wrapped_payload)
      
      # Synchronize: block loop here until pane responds
      cmd.wait_for_completion
      
      # Read the resulting states
      stdout_text, stderr_text, exit_code = cmd.read_outputs
      cmd.cleanup!

      # Construct execution record
      @results << CommandResult.new(
        command: cmd_str,
        stdin: "", 
        stdout: stdout_text,
        stderr: stderr_text,
        exit_code: exit_code
      )

      # Handle command failure conditions
      if exit_code != 0
        puts "\n[!] Command failed with exit code #{exit_code}. Halting execution flow."
        @pane.alert_failure!
        @failed = true
        break
      end
    end

    finalize_session
  end

  private def finalize_session
    if @failed
      puts "The right-hand execution pane has been left open for debugging."
    else
      @pane.close!
    end

    File.write(@output_yaml_path, @results.to_yaml)
    puts "Execution logs saved to: #{@output_yaml_path}"
  end
end

# =============================================================================
# 4. ENTRY POINT
# =============================================================================
if ARGV.size < 2
  puts "Usage: tmux.run <output_log.yaml> \"command 1\" \"command 2\" ..."
  exit 1
end

output_file = ARGV[0]
commands_to_run = ARGV[1..]

# Fire up the engine
runner = ExecutionRunner.new(commands_to_run, output_file)
runner.run!
