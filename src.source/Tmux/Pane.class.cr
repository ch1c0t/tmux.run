getter id : String
getter log_path : String

def initialize
  @log_path = "#{Config.target_dir}/#{Config.timestamp}.visual_stream.log"
  File.write(@log_path, "") 

  # FIXED: Split window launches a completely standalone, clean interactive shell session instantly.
  # This guarantees that the pane can never be destroyed or affected by signals in our parent loop.
  @id = `tmux split-window -h -P 'exec $SHELL'`.strip
  
  # Wait briefly for the target shell prompt to load its rc configurations
  sleep(200.milliseconds)

  # Start a detached background file tracker streaming directly onto the pane layout.
  # The leading space prevents the line from being added to your shell history.
  Process.run("tmux", ["send-keys", "-t", @id, " tail -f -n +1 #{@log_path} & tail_pid=$!", "Enter"])
end

include Methods
