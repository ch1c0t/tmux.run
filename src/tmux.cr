module Tmux

  class Pane
    module Private
      # Helper 1: Queries the active window context for our custom metadata option tag
      private def find_existing_pane_id : String?
        query = `tmux list-panes -F "\#{pane_id}" -f "\#{==:\#{@tmuxrun_pane},1}" 2>/dev/null`.strip
        query.empty? ? nil : query
      end
      
      # Helper 2: Clears out active log followers from previous failed or debug runs
      private def clear_lingering_background_jobs
        Process.run("tmux", ["send-keys", "-t", @id, "C-c"])
        sleep(50.milliseconds)
        Process.run("tmux", ["send-keys", "-t", @id, " kill $tail_pid", "Enter"])
        sleep(50.milliseconds)
      end
      
      # Helper 3: Splits the window according to focus configurations and sets the metadata tag
      private def spawn_and_tag_new_pane : String
        detach_flag = Config.change_focus? ? "" : "-d"
        pane_id = `tmux split-window -h #{detach_flag} -P 'exec $SHELL'`.strip
        sleep(200.milliseconds)
      
        Process.run("tmux", ["set-option", "-p", "-t", pane_id, "@tmuxrun_pane", "1"])
        pane_id
      end
      
      # Helper 4: Hooks up the high-precision text mirror follower
      private def attach_log_follower
        Process.run("tmux", ["send-keys", "-t", @id, " tail -f -n +1 #{@log_path} & tail_pid=$!", "Enter"])
      end
    end
  
    module Public
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
    end
  
    getter id : String
    getter log_path : String
    
    def initialize
      @log_path = "#{Config.target_dir}/#{Config.timestamp}.visual_stream.log"
      File.write(@log_path, "") 
    
      if existing_id = find_existing_pane_id
        @id = existing_id
        clear_lingering_background_jobs
      else
        @id = spawn_and_tag_new_pane
      end
    
      attach_log_follower
    end
    
    include Private
    include Public
  end
end