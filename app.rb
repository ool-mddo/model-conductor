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
    namespace 'conduct' do
      params do
        requires :network, type: String, desc: 'Network name'
      end
      namespace ':network' do
        desc 'Test L3 reachability with test-pattern for multiple snapshot in a network'
        params do
          requires :snapshots, type: Array[String], desc: 'List of snapshot to test'
          requires :test_pattern, type: Hash, desc: 'Reachability test pattern definitions'
        end
        post 'reachability' do
          tester = ReachTester.new(params[:test_pattern])
          reach_results = tester.exec_all_traceroute_tests(params[:network], params[:snapshots])
          converter = ReachResultConverter.new(reach_results)

          # reply
          {
            reach_results:,
            reach_results_summary: converter.summary,
            reach_results_summary_table: converter.full_table
          }
        end

        desc 'Get topology diff'
        params do
          requires :src_ss, type: String, desc: 'Source snapshot name'
          requires :dst_ss, type: String, desc: 'Destination snapshot name'
          optional :upper_layer3, type: Boolean, desc: 'Diff with layers upper layer3', default: false
        end
        get 'snapshot_diff/:src_ss/:dst_ss' do
          # reply
          rest_api.fetch_topology_diff(params[:network], params[:src_ss], params[:dst_ss],
                                       upper_layer3: params[:upper_layer3])
        end

        params do
          requires :snapshot, type: String, desc: 'Snapshot name'
        end
        namespace ':snapshot' do
          desc 'Post (generate and register) topology data from configs'
          params do
            requires :label, type: String, desc: 'Label of the network/snapshot'
            optional :phy_ss_only, type: Boolean, desc: 'Physical snapshot only'
            optional :use_parallel, type: Boolean, desc: 'Use parallel'
            optional :off_node, type: String, desc: 'Node name to down'
            optional :off_intf_re, type: String, desc: 'Interface name to down (regexp)'
          end
          post 'topology' do
            # scenario
            topology_generator = TopologyGenerator.new
            snapshot_dict = topology_generator.generate_snapshot_dict(params[:network], params[:snapshot],
                                                                      params[:label], params)
            topology_generator.convert_config_to_query(snapshot_dict)
            topology_generator.convert_query_to_topology(snapshot_dict, use_parallel: params[:use_parallel])

            # reply
            snapshot_dict
          end

          desc 'Subsets of a snapshot'
          get 'subsets' do
            # NOTE: snapshot = both physical/logical
            topology_data = rest_api.fetch_topology_data(params[:network], params[:snapshot])
            nws = Netomox::Topology::DisconnectedVerifiableNetworks.new(topology_data)
            # reply
            nws.find_all_network_sets.to_array
          end

          desc 'Subsets diff of all snapshots derive from a physical snapshot (to compare before/after linkdown)'
          params do
            optional :min_score, type: Integer, desc: 'Minimum score to report', default: 0
          end
          get 'subsets_diff' do
            # NOTE: snapshot = physical
            snapshot_patterns = rest_api.fetch_snapshot_patterns(params[:network], params[:snapshot])
            network_sets_diffs = snapshot_patterns.map do |snapshot_pattern|
              source_snapshot = snapshot_pattern[:source_snapshot_name]
              target_snapshot = snapshot_pattern[:target_snapshot_name]
              NetworkSetsDiff.new(params[:network], source_snapshot, target_snapshot)
            end
            # reply
            network_sets_diffs.map(&:to_data).reject { |d| d[:score] < params[:min_score] }
          end
        end
      end
    end
    # rubocop:enable Metrics/BlockLength
  end
end
