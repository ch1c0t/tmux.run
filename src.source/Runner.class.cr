include Getters
include Finish
include Run

def initialize(@commands : Array(String))
  unless ENV.has_key?("TMUX")
    puts "Error: This program must be run inside an active Tmux session."
    exit 1
  end

  @pane = Tmux::Pane.new
  @run_id = Process.pid
  @results = [] of CommandResult
  @failed = false

  puts "Allocated Right Visual Tmux Pane: #{@pane.id}"
end
