# frozen_string_literal: true

require 'grape'
require 'lib/model_conductor'

module ModelConductor
  # Rest aapi base class
  class RestApiBase < Grape::API
    format :json
    logger ModelConductor.logger

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
end
