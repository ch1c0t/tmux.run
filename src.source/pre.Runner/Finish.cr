private def finish
  if @failed
    puts "The right half PTY tracking pane remains open for debugging."
  else
    @pane.close!
  end

  File.write(@output_yaml_path, @results.to_yaml)
  puts "High-precision PTY serialization complete: #{@output_yaml_path}"
end
