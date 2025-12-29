# frozen_string_literal: true

require 'grape'
require 'lib/api/rest_api_base'
require_relative 'snapshot/subsets'
require_relative 'snapshot/splice_topology'
require_relative 'snapshot/topology'
require_relative 'snapshot/candidate_topology'

module ModelConductor
  module ApiRoute
    # namespace /snapshot
    class Snapshot < RestApiBase
      params do
        requires :snapshot, type: String, desc: 'Snapshot name'
      end
      namespace ':snapshot' do
        mount ApiRoute::Subsets
        mount ApiRoute::SpliceTopology
        mount ApiRoute::Topology
        mount ApiRoute::CandidateTopology
      end
    end
  end
end
