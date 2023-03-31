# frozen_string_literal: true

$LOAD_PATH.unshift File.dirname(__FILE__)

require_relative 'lib/api/rest_api_base'
require_relative 'lib/api/conduct'

module ModelConductor
  # model-conductor REST API definition
  class ModelConductorRestApi < RestApiBase
    mount ApiRoute::Conduct
  end
end
