# frozen_string_literal: true

require 'csv'
require 'fileutils'
require 'json'

module ModelConductor
  # common operation
  class OperationBase
    def initialize
      @logger = ModelConductor.logger
      @rest_api = ModelConductor.rest_api
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
