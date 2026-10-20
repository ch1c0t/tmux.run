def run!
  run_commands
  finish
end

include StripANSI

def run_commands
  @commands.each_with_index do |cmd_str, index|
    puts "Processing inside PTY #{index + 1}/#{@commands.size}: '#{cmd_str}'"
    
    @pane.stream_command_mirror(cmd_str)

    cmd = PTY::Command.new(cmd_str)
    raw_pty_output, exit_code = cmd.execute_inside_pty do |live_chunk|
      @pane.stream_output(live_chunk)
    end

    @results << CommandResult.new(
      command: cmd_str,
      output: strip_ansi(raw_pty_output),
      exit_code: exit_code
    )

    if exit_code != 0
      puts "\n[!] PTY Command broke with code #{exit_code}. Terminating automation."
      @pane.alert_failure!
      @failed = true
      break
    end
  end
end
