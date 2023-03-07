# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'json'
require_relative 'mddo_rest_api_client'

module LinkdownSimulation
  # scenario base class
  class ScenarioBase
    def initialize(logger)
      @logger = logger
      @rest_api = MddoRestApiClient.new(logger)
    end

    private

    # @param [String] str JSON string
    # @param [Boolean] symbolize_names (Optional, default: true)
    # @return [Object] parsed data
    def parse_json_str(str, symbolize_names: true)
      JSON.parse(str, { symbolize_names: })
    end
  end
end
