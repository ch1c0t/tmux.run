module Config
  # Class variables allow us to compute these properties once at boot
  @@username : String = ENV["USER"]? || "default"
  @@now : Time = Time.local
  
  # Computes the dot-separated string pattern
  def self.timestamp : String
    calendar_str = @@now.to_s("%Y%m%d_%H%M%S")
    unixtime = @@now.to_unix
    "#{calendar_str}.#{unixtime}"
  end
  
  def self.target_dir : String
    "/tmp/#{@@username}/tmux.run"
  end
  
  def self.output_yaml_path : String
    "#{target_dir}/#{timestamp}.yaml"
  end
end