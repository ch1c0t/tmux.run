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
end
