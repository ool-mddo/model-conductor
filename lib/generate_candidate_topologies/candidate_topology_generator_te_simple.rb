# frozen_string_literal: true

require_relative 'netomox_topology'

module ModelConductor
  # candidate topology generator (for TE usecase with simple-selection)
  class CandidateTopologyGenerator
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
  end
end
