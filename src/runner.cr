class Runner
  module Finish
    private def finish
      if @failed
        puts "The right half PTY tracking pane remains open for debugging."
      else
        @pane.close!
      end
    
      File.write(output_yaml_path, @results.to_yaml)
      puts "High-precision PTY serialization complete: #{output_yaml_path}"
    end
  end

  module Getters
    memoize def username : String
      ENV["USER"]? || "default"
    end
    
    memoize def target_dir : String
      dir = "/tmp/#{username}/tmux.run"
      FileUtils.mkdir_p dir
      dir
    end
    
    memoize def output_yaml_path : String
      now = Time.local
      calendar_str = now.to_s("%Y%m%d_%H%M%S")
      unixtime = now.to_unix
      timestamp = "#{calendar_str}.#{unixtime}"
    
      "#{target_dir}/#{timestamp}.yaml"
    end
  end

  include Getters
  include Finish
  
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
  
  def run!
    @commands.each_with_index do |cmd_str, index|
      puts "Processing inside PTY #{index + 1}/#{@commands.size}: '#{cmd_str}'"
      
      @pane.stream_command_mirror(cmd_str)
  
      cmd = PtyCommand.new(cmd_str, index, @run_id)
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
  
    finish
  end
end