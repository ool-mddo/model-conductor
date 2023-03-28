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
  # rubocop:disable Metrics/ClassLength

  # model-conductor REST API definition
  class ModelConductorRestApi < RestApiBase
    # rubocop:disable Metrics/BlockLength
    namespace 'conduct' do
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

        desc 'Test L3 reachability with test-pattern for multiple snapshot in a network'
        params do
          requires :snapshots, type: Array[String], desc: 'List of snapshot to test'
          requires :test_pattern, type: Hash, desc: 'Reachability test pattern definitions'
        end
        post 'reachability' do
          network, snapshots, test_pattern = %i[network snapshots test_pattern].map { |key| params[key] }
          tester = ReachTester.new(test_pattern)
          reach_results = tester.exec_all_traceroute_tests(network, snapshots)
          converter = ReachResultConverter.new(reach_results)

          # response
          {
            reach_results:,
            reach_results_summary: converter.summary,
            reach_results_summary_table: converter.full_table
          }
        end

        params do
          requires :src_ss, type: String, desc: 'Source snapshot name'
          requires :dst_ss, type: String, desc: 'Destination snapshot name'
          optional :upper_layer3, type: Boolean, desc: 'Diff with layers upper layer3', default: false
        end
        resource 'snapshot_diff/:src_ss/:dst_ss' do
          desc 'Get topology diff'
          get do
            network, src_ss, dst_ss, upl3 = %i[network src_ss dst_ss upper_layer3].map { |key| params[key] }
            # response
            rest_api.fetch_topology_diff(network, src_ss, dst_ss, upper_layer3: upl3)
          end

          desc 'Get topology diff and post (overwrite) to destination snapshot'
          post do
            network, src_ss, dst_ss, upl3 = %i[network src_ss dst_ss upper_layer3].map { |key| params[key] }
            topology_diff = rest_api.fetch_topology_diff(network, src_ss, dst_ss, upper_layer3: upl3)
            rest_api.post_topology_data(network, dst_ss, topology_diff)
            # response
            {}
          end
        end

        desc 'Get converted topology and post it as other topology'
        params do
          requires :src_ss, type: String, desc: 'Source snapshot name'
          requires :dst_ss, type: String, desc: 'Destination snapshot name'
          requires :table_origin, type: String, desc: 'Origin snapshot name to create convert table'
        end
        post 'ns_convert/:src_ss/:dst_ss' do
          network, src_ss, dst_ss, origin_ss = %i[network src_ss dst_ss table_origin].map { |key| params[key] }

          rest_api.init_ns_convert_table(network, origin_ss)
          converted_topology_data = rest_api.fetch_converted_topology_data(network, src_ss)
          rest_api.post_topology_data(network, dst_ss, converted_topology_data)
          # response
          {}
        end

        params do
          requires :snapshot, type: String, desc: 'Snapshot name'
        end
        namespace ':snapshot' do
          desc 'Post (generate and register) topology data from configs'
          params do
            requires :label, type: String, desc: 'Label of the network/snapshot'
            optional :phy_ss_only, type: Boolean, desc: 'Physical snapshot only', default: false
            optional :use_parallel, type: Boolean, desc: 'Use parallel', default: false
            optional :off_node, type: String, desc: 'Node name to down'
            optional :off_intf_re, type: String, desc: 'Interface name to down (regexp)'
          end
          post 'topology' do
            network, snapshot, label, use_parallel = %i[network snapshot label use_parallel].map { |key| params[key] }
            # scenario
            topology_generator = TopologyGenerator.new
            snapshot_dict = topology_generator.generate_snapshot_dict(network, snapshot, label, params)
            topology_generator.convert_config_to_query(snapshot_dict)
            topology_generator.convert_query_to_topology(snapshot_dict, use_parallel:)

            # response
            snapshot_dict
          end

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
    # rubocop:enable Metrics/BlockLength
  end
  # rubocop:enable Metrics/ClassLength
end
