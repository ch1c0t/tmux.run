getter raw_string : String
getter status_path : String

def initialize(@raw_string, index : Int32, run_id : Int64)
  @status_path = "#{Config.target_dir}/#{Config.timestamp}.pty_status_#{run_id}_#{index}.txt"
end

def execute_inside_pty : Tuple(String, Int32)
  master_fd, slave_fd = allocate_pty

  pid = C.fork
  if pid < 0
    raise "Error: OS process fork failed."
  elsif pid == 0
    # Inside the Child Process sandbox
    spawn_child(slave_fd)
  else
    # Inside the Parent Process proxy monitor
    output_buffer = stream_master_output(master_fd, slave_fd)
    exit_code = wait_for_status_file

    {output_buffer, exit_code}
  end
end

include Helpers
