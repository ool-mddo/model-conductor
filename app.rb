# frozen_string_literal: true

require 'fileutils'
require 'grape'
require 'json'
require_relative 'lib/mddo_rest_api_client'
require_relative 'lib/nw_subsets/disconnected_verifiable_networks'
require_relative 'lib/nw_subsets/network_sets_diff'
require_relative 'lib/topology_generator'

# model-conductor REST API definition
class TopologyConductorRestApi < Grape::API
  format :json

  helpers do
    def logger
      TopologyConductorRestApi.logger
    end
  end

  namespace 'model-conductor' do
    desc 'Post (generate and register) topology data from configs'
    params do
      requires :model_info, type: Array, desc: 'List of model-info'
      optional :phy_ss_only, type: Boolean, desc: 'Physical snapshot only'
      optional :off_node, type: String, desc: 'Node name to down'
      optional :off_intf_re, type: String, desc: 'Interface name to down (regexp)'
    end
    # receive model_info
    post 'generate-topology' do
      logger.debug "[model-conductor/generate-topology] params: #{params}"
      # scenario
      topology_generator = ModelConductor::TopologyGenerator.new(logger)
      topology_generator.delete_all_data_dir(params['model_info'])
      snapshot_dict = topology_generator.generate_snapshot_dict(params['model_info'], params)
      netoviz_index_data = topology_generator.convert_query_to_topology(snapshot_dict)
      topology_generator.save_netoviz_index(netoviz_index_data)
      {
        method: 'POST',
        path: '/model-conductor/generate-topology',
        snapshot_dict:
      }
    end

    namespace 'subsets' do
      desc 'Get subsets of a snapshot'
      params do
        requires :network, type: String, desc: 'Network name'
        requires :snapshot, type: String, desc: 'Snapshot name'
      end
      get ':network/:snapshot' do
        rest_api = ModelConductor::MddoRestApiClient.new(logger)
        topology_data = rest_api.fetch_topology_data(params[:network], params[:snapshot])
        nws = Netomox::Topology::DisconnectedVerifiableNetworks.new(topology_data)
        subsets = nws.find_all_network_sets.to_array
        {
          method: 'GET',
          path: "/model-conductor/subsets/#{params[:network]}/#{params[:subset]}",
          subsets:
        }
      end

      desc 'Get subsets comparison between physical and logical snapshots in a network'
      params do
        requires :network, type: String, desc: 'Network name'
        requires :snapshot, type: String, desc: 'Physical snapshot name'
        optional :min_score, type: Integer, desc: 'Minimum score to report', default: 0
      end
      get ':network/:snapshot/compare' do
        rest_api = ModelConductor::MddoRestApiClient.new(logger)
        snapshot_patterns = rest_api.fetch_snapshot_patterns(params[:network], params[:snapshot])
        network_sets_diffs = snapshot_patterns.map do |snapshot_pattern|
          source_snapshot = snapshot_pattern[:source_snapshot_name]
          target_snapshot = snapshot_pattern[:target_snapshot_name]
          ModelConductor::NetworkSetsDiff.new(rest_api, params[:network], source_snapshot, target_snapshot)
        end
        network_sets_diffs = network_sets_diffs.map(&:to_data).reject { |d| d[:score] < params[:min_score] }
        {
          method: 'GET',
          path: "/model-conductor/subsets/#{params[:network]}/#{params[:subset]}/compare",
          network_sets_diffs:
        }
      end
    end
  end
end
