module Tmux

  class Pane
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
end