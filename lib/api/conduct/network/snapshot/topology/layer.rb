# frozen_string_literal: true

require 'lib/api/rest_api_base'
require_relative 'layer/policies'

module ModelConductor
  module ApiRoute
    # api layer
    class Layer < RestApiBase
      params do
        requires :layer, type: String, desc: 'Network layer'
      end
      namespace ':layer' do
        mount ApiRoute::Policies
      end
    end
  end
end
