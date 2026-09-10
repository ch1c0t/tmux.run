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
