# frozen_string_literal: true

require 'grape'
require_relative 'network/ns_convert'
require_relative 'network/reachability'
require_relative 'network/snapshot'
require_relative 'network/snapshot_diff'
require_relative 'network/model_merge'

module ModelConductor
  module ApiRoute
    # namespace /network
    class Network < Grape::API
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
      end
    end
  end
end
