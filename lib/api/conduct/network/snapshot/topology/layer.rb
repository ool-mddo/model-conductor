# frozen_string_literal: true

require 'grape'
require_relative 'layer/policies'

module ModelConductor
  module ApiRoute
    # api layer
    class Layer < Grape::API
      params do
        requires :layer, type: String, desc: 'Network layer'
      end
      namespace ':layer' do
        mount ApiRoute::Policies
      end
    end
  end
end
