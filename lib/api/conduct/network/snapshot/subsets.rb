# frozen_string_literal: true

require 'grape'
require 'lib/nw_subsets/disconnected_verifiable_networks'
require 'lib/nw_subsets/network_sets_diff'

module ModelConductor
  module ApiRoute
    # api subsets and subsets_diff
    class Subsets < Grape::API
      desc 'Subsets of a snapshot'
      get 'subsets' do
        network, snapshot = %i[network snapshot].map { |key| params[key] }
        # NOTE: snapshot = both physical/logical
        topology_data = rest_api.fetch_topology_data(network, snapshot)
        nws = Netomox::Topology::DisconnectedVerifiableNetworks.new(topology_data)
        # response
        nws.find_all_network_sets.to_array
      end

      desc 'Subsets diff of all snapshots derive from a physical snapshot (to compare before/after linkdown)'
      params do
        optional :min_score, type: Integer, desc: 'Minimum score to report', default: 0
      end
      get 'subsets_diff' do
        network, snapshot, min_score = %i[network snapshot min_score].map { |key| params[key] }
        # NOTE: snapshot = physical
        snapshot_patterns = rest_api.fetch_snapshot_patterns(network, snapshot)
        network_sets_diffs = snapshot_patterns.map do |snapshot_pattern|
          source_snapshot = snapshot_pattern[:source_snapshot_name]
          target_snapshot = snapshot_pattern[:target_snapshot_name]
          NetworkSetsDiff.new(network, source_snapshot, target_snapshot)
        end
        # response
        network_sets_diffs.map(&:to_data).reject { |d| d[:score] < min_score }
      end
    end
  end
end
