# frozen_string_literal: true

require 'grape'
require_relative 'snapshot/subsets'
require_relative 'snapshot/topology'
require_relative 'snapshot/splice_topology'

module ModelConductor
  module ApiRoute
    # namespace /snapshot
    class Snapshot < Grape::API
      params do
        requires :snapshot, type: String, desc: 'Snapshot name'
      end
      namespace ':snapshot' do
        mount ApiRoute::Subsets
        mount ApiRoute::Topology
        mount ApiRoute::SpliceTopology
      end
    end
  end
end
