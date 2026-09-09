class PtyCommand
  module Helpers
    # Helper 1: Allocates the master and slave kernel file descriptors
    private def allocate_pty : Tuple(Int32, Int32)
      if C.openpty(out master_fd, out slave_fd, nil, nil, nil) == -1
        raise "Error: OS failed to allocate high-precision PTY descriptors."
      end
      {master_fd, slave_fd}
    end
    
    # Helper 2: Sets up the slave terminal environment and hands control to the shell
    private def spawn_child(slave_fd : Int32) : NoReturn
      C.login_tty(slave_fd)
      ENV["TERM"] = "xterm-256color"
      
      # Overwrite child memory stack with a fresh subshell execution block
      Process.exec("/bin/sh", ["-c", "( #{@raw_string} ); echo $? > #{@status_path}"])
      C._exit(1)
    end
    
    # Helper 3: Reads all available byte strings from the master PTY buffer
    private def stream_master_output(master_fd : Int32, slave_fd : Int32) : String
      # Close parent handle to the slave side to avoid descriptor resource leaks
      IO::FileDescriptor.new(slave_fd, close_on_finalize: true).close
    
      master_io = IO::FileDescriptor.new(master_fd, close_on_finalize: true)
      buffer = IO::Memory.new
    
      begin
        io_buffer = Bytes.new(4096)
        while (bytes_read = master_io.read(io_buffer)) > 0
          buffer.write(io_buffer[0, bytes_read])
        end
      rescue IO::Error
        # EIO is normally thrown and caught when the slave process drops out
      end
    
      buffer.to_s
    end
    
    # Helper 4: Blocks until the status sync file has completed writing
    private def wait_for_status_file : Int32
      while !File.exists?(@status_path)
        sleep(50.milliseconds)
      end
    
      exit_code = File.read(@status_path).strip.to_i
      File.delete(@status_path) if File.exists?(@status_path)
      exit_code
    end
  end

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
end