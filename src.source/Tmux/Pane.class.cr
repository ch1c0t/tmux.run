getter id : String
getter log_path : String

def initialize
  run_id = Process.pid
  @log_path = "/tmp/tmux_visual_stream_#{run_id}.log"
  File.write(@log_path, "") 

  # FIXED: Split window launches a completely standalone, clean interactive shell session instantly.
  # This guarantees that the pane can never be destroyed or affected by signals in our parent loop.
  @id = `tmux split-window -h -P 'exec $SHELL'`.strip
  
  # Wait briefly for the target shell prompt to load its rc configurations
  sleep(200.milliseconds)

  # Start a detached background file tracker streaming directly onto the pane layout.
  # The leading space prevents the line from being added to your shell history.
  Process.run("tmux", ["send-keys", "-t", @id, " tail -f #{@log_path} & tail_pid=$!", "Enter"])
end

def stream_command_mirror(cmd_str : String)
  File.open(@log_path, "a") do |f|
    f.puts "\n\e[1;34m[Running PTY]: #{cmd_str}\e[0m"
  end
end

def stream_output(output_text : String)
  File.open(@log_path, "a") do |f|
    f.write(output_text.gsub("\r\n", "\n").to_slice)
  end
end

def alert_failure!
  File.open(@log_path, "a") do |f|
    f.puts "\n\e[1;31m[tmux.run] Execution halted inside PTY. Skipped remaining steps.\e[0m\n"
  end
  # Wait for file synchronization before stopping the tracker
  sleep(100.milliseconds)

  # Kill only the background tail process inside that pane, returning you to the intact shell prompt
  Process.run("tmux", ["send-keys", "-t", @id, " kill $tail_pid", "Enter"])
end

def close!
  # Clean up the tail job if it's still running, then close the pane
  Process.run("tmux", ["send-keys", "-t", @id, " kill $tail_pid", "Enter"])
  sleep(50.milliseconds)
  Process.run("tmux", ["kill-pane", "-t", @id])
  File.delete(@log_path) if File.exists?(@log_path)
end
