# frozen_string_literal: true

require 'grape'
require_relative 'mddo_rest_api_client'

# Model conductor module
module ModelConductor
  # Rest aapi base class
  class RestApiBase < Grape::API
    format :json

    helpers do
      # @return [Logger] Logger
      def logger
        RestApiBase.logger
      end

      # @return [MddoRestApiClient] REST API client
      def rest_api
        ModelConductor.rest_api
      end
    end
  end

  # module common logger
  @logger = RestApiBase.logger

  # rest api client (backend interface)
  @rest_api = MddoRestApiClient.new(@logger)

  module_function

  # @return [Logger] Logger
  def logger
    @logger
  end

  # @return [MddoRestApiClient] REST API client
  def rest_api
    @rest_api
  end
end
