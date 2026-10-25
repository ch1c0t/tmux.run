require_relative 'TmuxRunE2ESession'

describe "tmux.run end-to-end contract" do
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
