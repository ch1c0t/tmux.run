require_relative '../helper'

describe 'cli' do
  it 'prints a help message' do
    stdout = cli '--help'
    expect(stdout.first).to \
      start_with \
        'tmux.run is a CLI to run a list of commands sequentially, while also streaming'
  end
end
