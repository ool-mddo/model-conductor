# frozen_string_literal: true

module TopologyFixtures
  FIXTURE_DIR = File.join(__dir__, '..', 'fixtures')

  def load_fixture(filename)
    JSON.parse(File.read(File.join(FIXTURE_DIR, filename)), symbolize_names: false)
  end

  def load_fixture_sym(filename)
    JSON.parse(File.read(File.join(FIXTURE_DIR, filename)), symbolize_names: true)
  end
end

RSpec.configure do |config|
  config.include TopologyFixtures
end
