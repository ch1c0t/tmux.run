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
