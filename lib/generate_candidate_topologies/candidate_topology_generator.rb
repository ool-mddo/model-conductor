# frozen_string_literal: true

require 'netomox'
require_relative 'flow_data_table'

module Netomox
  module Topology
    # patch for Network
    class Network
      # @param [String] nw_ref Supporting network name
      # @param [String] node_ref Supporting node name
      # @return [nil, Netomox::Topology::Node]
      def find_node_by_support(nw_ref, node_ref)
        @nodes.find do |node|
          node.supports.find do |support|
            support.ref_network == nw_ref && support.ref_node == node_ref
          end
        end
      end
    end
  end
end

module ModelConductor
  # rubocop:disable Metrics/ClassLength

  # candidate topology generator
  class CandidateTopologyGenerator
    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @param [Hash] usecase_data
    def initialize(network, snapshot, usecase_data)
      @network = network
      @snapshot = snapshot
      # @see ModelConductor::ApiRoute::CandidateTopology
      # {
      #   "src1": <(GET /usecases/<usecase_name>/<src1>),
      #   "src2": <(GET /usecases/<usecase_name>/<src2>),
      #   ...
      # }
      @usecase = usecase_data
    end

    # rubocop:disable Metrics/MethodLength

    # @param [Integer] phase_number Phase number
    # @param [Integer] candidate_number Number of candidates
    # @return [nil, Array<Hash>]
    def generate_candidate_topologies(phase_number, candidate_number)
      unless %w[pni_te multi_region_te].include?(@usecase[:name])
        ModelConductor.logger.error "Unsupported usecase: #{@usecase[:name]}"
        return nil
      end

      # for pni_te/multi_region_te usecase
      if @usecase[:phase_candidate_opts].key?(:flow_data)
        ModelConductor.logger.info 'Generate candidate by flows'
        candidate_topologies_by_flows(phase_number, candidate_number)
      else
        ModelConductor.logger.info 'Generate candidate by simple select'
        candidate_topologies_by_simple_select(phase_number, candidate_number)
      end
    end
    # rubocop:enable Metrics/MethodLength

    private

    # @param [Netomox::Topology::MddoBgpPrefixSet] prefix_set
    # @param [Integer] policy_index Index number to omit from prefix-set
    # @return [nil, Netomox::Topology::MddoBgpPrefix]
    def update_prefixes_by_simple_select!(prefix_set, policy_index)
      if policy_index > prefix_set.prefixes.length
        ModelConductor.logger.error "policy unchanged out-of-range index #{policy_index} for prefix-set"
        nil
      else
        prefix_set.prefixes.delete_at(policy_index - 1)
      end
    end

    # @param [Integer] policy_index Index number to omit from prefix-set
    # @return [nil, Array(Netomox::Topology::Networks, Netomox::Topology::MddoBgpPrefix)]
    def generate_candidate_by_simple_select_for_te(policy_index)
      # always reload to avoid deep-copy problem...
      base_topology = read_base_topology
      # usecase params
      l3_node_name = @usecase[:phase_candidate_opts][:node]
      src_asn = @usecase[:params][:source_as][:asn]

      result = pickup_prefix_set(base_topology, l3_node_name, src_asn)
      if result[:error]
        ModelConductor.logger.error result[:message]
        return nil
      end

      # overwrite base_topology
      omitted_prefix = update_prefixes_by_simple_select!(result[:prefix_set], policy_index)

      # return modified topology data as candidate_pi
      [base_topology, omitted_prefix]
    end

    # @param [Integer] phase_number Phase number
    # @param [Integer] candidate_number Number of candidates
    # @return [Array<Hash>]
    def candidate_topologies_by_simple_select(phase_number, candidate_number)
      (1..candidate_number).map do |candidate_index|
        candidate_topology, omitted_policy = generate_candidate_by_simple_select_for_te(candidate_index)
        candidate_condition = { omit_index: candidate_index, omit_policy: omitted_policy.to_data }
        candidate_topology_info(phase_number, candidate_index, candidate_topology, candidate_condition)
      end
    end

    # @param [Integer] phase_number Phase number
    # @param [Integer] candidate_index Index of candidate model
    # @return [Hash] candidate topology metadata (including topology)
    def candidate_topology_info(phase_number, candidate_index, candidate_topology, candidate_condition)
      {
        network: @network,
        benchmark_snapshot: @snapshot,
        snapshot: "original_candidate_#{phase_number}#{candidate_index}",
        topology: candidate_topology.to_data,
        candidate_condition:
      }
    end

    # rubocop:disable Metrics/MethodLength

    # @param [Integer] phase_number Phase number
    # @param [Integer] candidate_number Number of candidates
    # @return [nil, Array<Hash>] nil for error
    def candidate_topologies_by_flows(phase_number, candidate_number)
      aggregated_flows = generate_aggregated_flows_for_pni_te
      if aggregated_flows.nil?
        ModelConductor.logger.error "Cannot operate aggregated flows in usecase:#{@usecase[:name]}"
        return nil
      end

      if aggregated_flows.length <= candidate_number
        ModelConductor.logger.warn "Candidate number to set #{aggregated_flows.length} because flows too little"
        candidate_number = aggregated_flows.length
      end
      (1..candidate_number).map do |candidate_index|
        target_flow = aggregated_flows[candidate_index - 1]
        candidate_topology = generate_candidate_by_flows_for_te(target_flow)
        candidate_topology_info(phase_number, candidate_index, candidate_topology, target_flow)
      end
    end
    # rubocop:enable Metrics/MethodLength

    # @return [Hash] {node, interface, expected_max_bandwidth} params in params/expected_traffic/original_targets
    def find_observe_point
      pc_opts = @usecase[:phase_candidate_opts] # alias
      observe_point = @usecase[:params][:expected_traffic][:original_targets].find do |t|
        t[:node] == pc_opts[:node] && t[:interface] == pc_opts[:interface]
      end

      if observe_point
        observe_point
      else
        pc_opts[:expected_max_bandwidth] = 8e8 # assume 80% of 10GbE
        pc_opts
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength

    # @return [Array<Hash>] Aggregated flows
    #   [{ prefixes: ["a.b.c.d/nn",...], rate: dddd.dd, diff: dd.dd }, ...]
    def generate_aggregated_flows_for_pni_te
      base_topology = read_base_topology
      # usecase params
      src_asn = @usecase[:params][:source_as][:asn]
      observe_point = find_observe_point
      # NOTE: max_bandwidth is bps string (like "0.8e9"),
      #   convert it to Mbps value (float number) because rate in flow-data is Mbps value
      max_bandwidth = observe_point[:expected_max_bandwidth].to_f / 1e6

      flow_data_table = FlowDataTable.new(@usecase[:phase_candidate_opts][:flow_data])
      result = pickup_prefix_set(base_topology, observe_point[:node], src_asn)
      if result[:error]
        ModelConductor.logger.error result[:message]
        return nil
      end

      prefix_set = result[:prefix_set]
      combination_count = prefix_set.prefixes.length # MAX: full-combinations
      flow_data_table.aggregated_flows_by_prefix(combination_count, prefix_set, max_bandwidth)
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

    # @param [Hash] aggregated_flow An entry of aggregated flows
    # @return [nil, Netomox::Topology::Networks]
    def generate_candidate_by_flows_for_te(aggregated_flow)
      # always reload to avoid deep-copy problem...
      base_topology = read_base_topology
      # usecase params
      l3_node_name = @usecase[:phase_candidate_opts][:node]
      src_asn = @usecase[:params][:source_as][:asn]

      result = pickup_prefix_set(base_topology, l3_node_name, src_asn)
      if result[:error]
        ModelConductor.logger.error result[:message]
        return nil
      end

      # overwrite base_topology
      update_prefixes_by_flows_for_te!(result[:prefix_set], aggregated_flow)

      # return modified topology data as candidate_pi
      base_topology
    end

    # @param [Netomox::Topology::MddoBgpPrefixSet] prefix_set
    # @param [Hash] aggregated_flow An aggregated flow entry
    # @return [void]
    def update_prefixes_by_flows_for_te!(prefix_set, aggregated_flow)
      prefix_set.prefixes.select! do |prefix|
        aggregated_flow[:prefixes].include?(prefix.prefix)
      end
    end

    # rubocop:disable Metrics/MethodLength

    # @param [Netomox::Topology::Networks] base_topology
    # @param [String] l3_node_name
    # @param [Integer] src_asn
    # @return [Hash]
    def pickup_prefix_set(base_topology, l3_node_name, src_asn)
      # pickup target network
      bgp_proc_nw = base_topology.find_network('bgp_proc')
      if bgp_proc_nw.nil?
        message = "network:bgp_proc is not found in #{base_topology.networks.map(&:name)}"
        return { error: true, message: }
      end

      # pickup target node (layer3 name -> bgp-proc node)
      bgp_proc_node = bgp_proc_nw.find_node_by_support('layer3', l3_node_name)
      if bgp_proc_node.nil?
        message = "bgp-proc node that supports layer3:#{l3_node_name} is not found in network:#{bgp_proc_nw.name}"
        return { error: true, message: }
      end

      prefix_set_name = "as#{src_asn}-advd-ipv4"
      prefix_set = find_prefix_set(bgp_proc_node, prefix_set_name)
      if prefix_set.nil?
        message = "prefix-set: #{prefix_set_name} is not found in node:#{bgp_proc_node.name}"
        return { error: true, message: }
      end

      # found prefix_set to modify for candidate topology
      { error: false, message: 'ok', prefix_set: }
    end
    # rubocop:enable Metrics/MethodLength

    # @param [Netomox::Topology::Node] bgp_proc_node
    # @param [String] prefix_set_name
    # @return [nil, Netomox::Topology::MddoBgpPrefixSet]
    def find_prefix_set(bgp_proc_node, prefix_set_name)
      bgp_proc_node.attribute.prefix_sets.find do |pfx_set|
        pfx_set.name =~ /#{prefix_set_name}/
      end
    end

    # @return [Netomox::Topology::Networks] topology object
    def read_base_topology
      ModelConductor.rest_api.fetch_topology_object(@network, @snapshot)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
