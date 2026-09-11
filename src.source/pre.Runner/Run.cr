def run!
  run_commands
  finish
end

include StripANSI

def run_commands
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
