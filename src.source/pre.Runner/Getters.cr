memoize def username : String
  ENV["USER"]? || "default"
end

memoize def target_dir : String
  dir = "/tmp/#{username}/tmux.run"
  FileUtils.mkdir_p dir
  dir
end

memoize def timestamp : String
  now = Time.local
  calendar_str = now.to_s("%Y%m%d_%H%M%S")
  unixtime = now.to_unix
  "#{calendar_str}.#{unixtime}"
end

memoize def output_yaml_path : String
  "#{target_dir}/#{timestamp}.yaml"
end
