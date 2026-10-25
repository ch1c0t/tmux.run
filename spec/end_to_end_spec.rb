# frozen_string_literal: true

require "fileutils"
require "open3"
require "securerandom"
require "shellwords"
require "tmpdir"
require "yaml"

# Runs the compiled CLI inside a disposable tmux session. Using a distinct tmux
# socket and USER per example keeps the suite isolated from the developer's
# interactive session and from other test runs.
class TmuxRunE2ESession
  BINARY = File.expand_path("../bin/tmux.run", __dir__)
  WAIT_TIMEOUT = 15

  attr_reader :output_dir, :root_pane_id, :username, :session_name, :temp_dir

  def initialize
    raise "Build bin/tmux.run before running end-to-end specs" unless File.executable?(BINARY)

    token = SecureRandom.hex(4)
    @socket_name = "trspec#{Process.pid}#{token}"
    @session_name = "trspec_#{Process.pid}_#{token}"
    @username = "tmuxrun_spec_#{Process.pid}_#{token}"
    @output_dir = File.join("/tmp", @username, "tmux.run")
    @temp_dir = Dir.mktmpdir("tmux-run-e2e-")

    start_server
  rescue StandardError
    close
    raise
  end

  def start(commands, change_focus: false)
    raise ArgumentError, "at least one command is required" if commands.empty?

    token = SecureRandom.hex(4)
    stdout_path = File.join(temp_dir, "#{token}.stdout")
    status_path = File.join(temp_dir, "#{token}.status")
    prefix = change_focus ? "TMUXRUN_CHANGE_FOCUS=true " : ""
    invocation = Shellwords.join([BINARY, *commands])
    shell_line = "#{prefix}#{invocation} > #{Shellwords.escape(stdout_path)} 2>&1; " \
                 "printf '%s\\n' $? > #{Shellwords.escape(status_path)}"

    send_keys(@root_pane_id, shell_line)
    press_enter(@root_pane_id)

    {stdout_path: stdout_path, status_path: status_path, commands: commands}
  end

  def run(commands, change_focus: false, timeout: WAIT_TIMEOUT)
    wait(start(commands, change_focus: change_focus), timeout: timeout)
  end

  def wait(handle, timeout: WAIT_TIMEOUT)
    wait_until(timeout: timeout, description: "tmux.run to finish") do
      File.file?(handle.fetch(:status_path))
    end

    {
      cli_exit_status: Integer(File.read(handle.fetch(:status_path)).strip),
      stdout: File.read(handle.fetch(:stdout_path)),
      commands: handle.fetch(:commands)
    }
  end

  def wait_until(timeout: WAIT_TIMEOUT, description: "condition")
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end

    raise "Timed out waiting for #{description}; panes: #{pane_rows.inspect}"
  end

  def pane_rows
    format = ['#{pane_id}', '#{pane_active}', '#{@tmuxrun_pane}'].join("\t")
    tmux("list-panes", "-t", session_name, "-F", format).lines.map do |line|
      pane_id, active, tagged = line.chomp.split("\t", -1)
      {id: pane_id, active: active == "1", tagged: tagged == "1"}
    end
  end

  def tagged_panes
    pane_rows.select { |pane| pane[:tagged] }
  end

  def active_pane_id
    pane_rows.find { |pane| pane[:active] }&.fetch(:id)
  end

  def capture_pane(pane_id)
    tmux("capture-pane", "-p", "-t", pane_id)
  end

  def artifacts
    yaml_paths = Dir.glob(File.join(output_dir, "*.yaml"))
    log_paths = Dir.glob(File.join(output_dir, "*.visual_stream.log"))
    raise "Expected one YAML result in #{output_dir}, got #{yaml_paths.inspect}" unless yaml_paths.one?
    raise "Expected one human-readable stream log in #{output_dir}, got #{log_paths.inspect}" unless log_paths.one?

    {
      yaml_path: yaml_paths.fetch(0),
      log_path: log_paths.fetch(0),
      results: YAML.safe_load_file(yaml_paths.fetch(0))
    }
  end

  def close
    if @socket_name
      tmux_process("kill-server")
    end
    FileUtils.rm_rf(File.join("/tmp", @username)) if @username
    FileUtils.remove_entry(temp_dir) if temp_dir && File.exist?(temp_dir)
  rescue StandardError
    # Best-effort cleanup must not mask the original assertion failure.
    nil
  end

  private

  def start_server
    shell = "env -u TMUXRUN_CHANGE_FOCUS USER=#{username} SHELL=/bin/bash bash --noprofile --norc"
    tmux("new-session", "-d", "-s", session_name, "-x", "120", "-y", "40", shell)
    @root_pane_id = tmux("list-panes", "-t", session_name, "-F", '#{pane_id}').lines.first&.strip
    raise "tmux did not create the root pane" unless @root_pane_id

    wait_until(description: "the test shell to start") do
      tmux("display-message", "-p", "-t", @root_pane_id, '#{pane_current_command}').strip == "bash"
    end
  end

  def send_keys(target, text)
    _stdout, stderr, status = tmux_process("send-keys", "-t", target, "-l", text)
    raise "tmux send-keys failed: #{stderr}" unless status.success?
  end

  def press_enter(target)
    _stdout, stderr, status = tmux_process("send-keys", "-t", target, "Enter")
    raise "tmux send-keys Enter failed: #{stderr}" unless status.success?
  end

  def tmux(*args)
    stdout, stderr, status = tmux_process(*args)
    raise "tmux #{args.join(' ')} failed: #{stderr}" unless status.success?

    stdout
  end

  def tmux_process(*args)
    # Do not let the test runner's own TMUX variables redirect these calls to
    # the user's server. Each helper command explicitly targets our -L socket.
    env = {"TMUX" => nil, "TMUX_PANE" => nil, "USER" => username, "SHELL" => "/bin/bash"}
    Open3.capture3(env, "tmux", "-L", @socket_name, *args)
  end
end

RSpec.describe "tmux.run end-to-end contract" do
  before do
    skip "tmux is required for end-to-end specs" unless system("tmux", "-V", out: File::NULL, err: File::NULL)

    @tmux_run = TmuxRunE2ESession.new
  end

  after do
    @tmux_run&.close
  end

  it "runs commands sequentially and saves human- and machine-readable output" do
    events = File.join(@tmux_run.temp_dir, "events.txt")
    commands = [
      "printf 'first\\n' >> #{Shellwords.escape(events)}; printf 'FIRST_OUTPUT\\n'",
      "printf 'second\\n' >> #{Shellwords.escape(events)}; printf 'SECOND_OUTPUT\\n'"
    ]

    @tmux_run.run(commands)
    artifacts = @tmux_run.artifacts

    expect(File.read(events)).to eq("first\nsecond\n")
    expect(artifacts[:results].map { |result| result.fetch("command") }).to eq(commands)
    expect(artifacts[:results].map { |result| result.fetch("exit_code") }).to eq([0, 0])
    expect(artifacts[:results][0].fetch("output")).to include("FIRST_OUTPUT")
    expect(artifacts[:results][1].fetch("output")).to include("SECOND_OUTPUT")
    expect(File.dirname(artifacts[:yaml_path])).to eq(@tmux_run.output_dir)
    expect(File.dirname(artifacts[:log_path])).to eq(@tmux_run.output_dir)
    expect(File.read(artifacts[:log_path])).to include("FIRST_OUTPUT", "SECOND_OUTPUT")
  end

  it "streams output into the tmux pane before the command completes" do
    handle = @tmux_run.start(["printf 'LIVE_OUTPUT_SENTINEL\\n'; sleep 2"])

    @tmux_run.wait_until(timeout: 5, description: "live output in the tracking pane") do
      pane = @tmux_run.tagged_panes.first
      pane && @tmux_run.capture_pane(pane.fetch(:id)).include?("LIVE_OUTPUT_SENTINEL")
    end

    @tmux_run.wait(handle)
    expect(@tmux_run.artifacts[:results].first.fetch("output")).to include("LIVE_OUTPUT_SENTINEL")
  end

  it "stops at the first failed command and leaves the tracking pane open" do
    events = File.join(@tmux_run.temp_dir, "events.txt")
    commands = [
      "printf 'first\\n' >> #{Shellwords.escape(events)}; printf 'BEFORE_FAILURE\\n'; exit 7",
      "printf 'second\\n' >> #{Shellwords.escape(events)}; printf 'MUST_NOT_RUN\\n'"
    ]

    @tmux_run.run(commands)
    artifacts = @tmux_run.artifacts

    expect(File.read(events)).to eq("first\n")
    expect(artifacts[:results].map { |result| result.fetch("command") }).to eq([commands.first])
    expect(artifacts[:results].first.fetch("exit_code")).to eq(7)
    expect(artifacts[:results].first.fetch("output")).to include("BEFORE_FAILURE")
    expect(artifacts[:results].first.fetch("output")).not_to include("MUST_NOT_RUN")
    expect(@tmux_run.tagged_panes.size).to eq(1)
  end

  it "closes the tracking pane after all commands succeed" do
    @tmux_run.run(["printf 'SUCCESS_SENTINEL\\n'"])

    expect(@tmux_run.tagged_panes).to be_empty
    expect(@tmux_run.pane_rows.size).to eq(1)
    expect(@tmux_run.artifacts[:results].first.fetch("exit_code")).to eq(0)
  end

  it "keeps focus on the original pane by default when a command fails" do
    @tmux_run.run(["exit 1"])

    expect(@tmux_run.tagged_panes.size).to eq(1)
    expect(@tmux_run.active_pane_id).to eq(@tmux_run.root_pane_id)
  end

  it "moves focus to the tracking pane when TMUXRUN_CHANGE_FOCUS=true" do
    @tmux_run.run(["exit 1"], change_focus: true)
    tagged_pane = @tmux_run.tagged_panes.fetch(0)

    expect(@tmux_run.active_pane_id).to eq(tagged_pane.fetch(:id))
  end
end
