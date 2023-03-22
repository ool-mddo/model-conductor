# frozen_string_literal: true

require 'fileutils'
require 'json'
require_relative 'lib/rest_api_base'
require_relative 'lib/nw_subsets/disconnected_verifiable_networks'
require_relative 'lib/nw_subsets/network_sets_diff'
require_relative 'lib/reach_test/reach_tester'
require_relative 'lib/reach_test/reach_result_converter'
require_relative 'lib/topology_generator'

module ModelConductor
  # model-conductor REST API definition
  class TopologyConductorRestApi < RestApiBase
    # rubocop:disable Metrics/BlockLength
    namespace 'model-conductor' do
      namespace 'topology' do
        desc 'Post (generate and register) topology data from configs'
        params do
          requires :network, type: String, desc: 'Network name'
          requires :snapshot, type: String, desc: 'Snapshot name'
          requires :label, type: String, desc: 'Label of the network/snapshot'
          optional :phy_ss_only, type: Boolean, desc: 'Physical snapshot only'
          optional :use_parallel, type: Boolean, desc: 'Use parallel'
          optional :off_node, type: String, desc: 'Node name to down'
          optional :off_intf_re, type: String, desc: 'Interface name to down (regexp)'
        end
        post ':network/:snapshot' do
          logger.debug "[model-conductor/generate-topology] params: #{params}"
          # scenario
          topology_generator = TopologyGenerator.new
          snapshot_dict = topology_generator.generate_snapshot_dict(params[:network], params[:snapshot],
                                                                    params[:label], params)
          topology_generator.convert_config_to_query(snapshot_dict)
          topology_generator.convert_query_to_topology(snapshot_dict, use_parallel: params[:use_parallel])
          {
            method: 'POST',
            path: "/model-conductor/topology/#{params[:network]}/#{params[:snapshot]}",
            snapshot_dict:
          }
        end
      end

      namespace 'subsets' do
        desc 'Get subsets of a snapshot'
        params do
          requires :network, type: String, desc: 'Network name'
          requires :snapshot, type: String, desc: 'Snapshot name'
        end
        get ':network/:snapshot' do
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
          snapshot_patterns = rest_api.fetch_snapshot_patterns(params[:network], params[:snapshot])
          network_sets_diffs = snapshot_patterns.map do |snapshot_pattern|
            source_snapshot = snapshot_pattern[:source_snapshot_name]
            target_snapshot = snapshot_pattern[:target_snapshot_name]
            NetworkSetsDiff.new(params[:network], source_snapshot, target_snapshot)
          end
          network_sets_diffs = network_sets_diffs.map(&:to_data).reject { |d| d[:score] < params[:min_score] }
          {
            method: 'GET',
            path: "/model-conductor/subsets/#{params[:network]}/#{params[:subset]}/compare",
            network_sets_diffs:
          }
        end
      end

      desc 'Reachability test with test-pattern'
      params do
        requires :network, type: String, desc: 'Network name'
        requires :snapshots, type: Array[String], desc: 'List of snapshot to test'
        requires :test_pattern, type: Hash, desc: 'Reachability test pattern definitions'
      end
      post 'reachability/:network' do
        tester = ReachTester.new(params[:test_pattern])
        reach_results = tester.exec_all_traceroute_tests(params[:network], params[:snapshots])
        converter = ReachResultConverter.new(reach_results)
        {
          method: 'POST',
          path: "/model-conductor/reachability/#{params[:network]}",
          reach_results:,
          reach_results_summary: converter.summary,
          reach_results_summary_table: converter.full_table
        }
      end
    end
    # rubocop:enable Metrics/BlockLength
  end
end
