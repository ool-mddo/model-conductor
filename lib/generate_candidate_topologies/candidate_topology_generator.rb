# frozen_string_literal: true

require 'netomox'
require_relative 'flow_data_table'
require_relative 'netomox_topology'

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

    # @param [String] src_asn Source AS number
    # @return [String]
    def target_prefix_set_name(src_asn)
      "as#{src_asn}-advd-ipv4"
    end

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

      result = base_topology.pickup_prefix_set(l3_node_name, target_prefix_set_name(src_asn))
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
      aggregated_flows = generate_aggregated_flows_for_te
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
    def generate_aggregated_flows_for_te
      base_topology = read_base_topology
      # usecase params
      src_asn = @usecase[:params][:source_as][:asn]
      observe_point = find_observe_point
      # NOTE: max_bandwidth is bps string (like "0.8e9"),
      #   convert it to Mbps value (float number) because rate in flow-data is Mbps value
      max_bandwidth = observe_point[:expected_max_bandwidth].to_f / 1e6

      flow_data_table = FlowDataTable.new(@usecase[:phase_candidate_opts][:flow_data])
      result = base_topology.pickup_prefix_set(observe_point[:node], target_prefix_set_name(src_asn))
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

      result = base_topology.pickup_prefix_set(l3_node_name, target_prefix_set_name(src_asn))
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

    # @return [Netomox::Topology::Networks] topology object
    def read_base_topology
      ModelConductor.rest_api.fetch_topology_object(@network, @snapshot)
    end
  end
  # rubocop:enable Metrics/ClassLength
end
