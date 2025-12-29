# frozen_string_literal: true

require 'grape'
require_relative 'rest_api_base'
require_relative 'conduct/network'

module ModelConductor
  module ApiRoute
    # namespace /conduct
    class Conduct < RestApiBase
      namespace 'conduct' do
        mount ApiRoute::Network
      end
    end
  end
end
