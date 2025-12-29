# frozen_string_literal: true

require 'grape'
require 'lib/api/rest_api_base'
require_relative 'network/ns_convert'
require_relative 'network/reachability'
require_relative 'network/snapshot'
require_relative 'network/snapshot_diff'
require_relative 'network/model_merge'
require_relative 'network/topology_ops'

module ModelConductor
  module ApiRoute
    # namespace /network
    class Network < RestApiBase
      params do
        requires :network, type: String, desc: 'Network name'
      end
      namespace ':network' do
        desc 'Delete all related resources of a network'
        delete do
          network = params[:network]
          rest_api.delete("/queries/#{network}")
          rest_api.delete("/topologies/#{network}")
          # response
          ''
        end

        mount ApiRoute::NsConvert
        mount ApiRoute::Reachability
        mount ApiRoute::Snapshot
        mount ApiRoute::SnapshotDiff
        mount ApiRoute::ModelMerge
        mount ApiRoute::TopologyOps
      end
    end
  end
end
