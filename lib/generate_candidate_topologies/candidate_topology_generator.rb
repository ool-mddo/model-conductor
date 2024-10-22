# frozen_string_literal: true

require_relative 'candidate_topology_generator_te_flow'
require_relative 'candidate_topology_generator_te_simple'
require_relative 'netomox_topology'

module ModelConductor
  # candidate topology generator (common functions)
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

    # @return [Netomox::Topology::Networks] topology object
    def read_base_topology
      ModelConductor.rest_api.fetch_topology_object(@network, @snapshot)
    end
  end
end
