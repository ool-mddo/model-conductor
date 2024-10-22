# frozen_string_literal: true

require_relative 'flow_data_table'
require_relative 'netomox_topology'

module ModelConductor
  # candidate topology generator (for TE usecase with flow-data)
  class CandidateTopologyGenerator
    private

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

    # @param [Netomox::Topology::MddoBgpPrefixSet] prefix_set
    # @param [Hash] aggregated_flow An aggregated flow entry
    # @return [void]
    def update_prefixes_by_flows_for_te!(prefix_set, aggregated_flow)
      prefix_set.prefixes.select! do |prefix|
        aggregated_flow[:prefixes].include?(prefix.prefix)
      end
    end

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
  end
end
