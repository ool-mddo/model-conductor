# frozen_string_literal: true

require_relative 'candidate_topology_generator_te_flow'
require_relative 'candidate_topology_generator_te_simple'
require_relative 'netomox_topology'

module ModelConductor
  # candidate topology generator (common functions)
  # noinspection SpellCheckingInspection
  class CandidateTopologyGenerator
    # allowed usecases
    ALLOWED_USECASES = %w[pni_te multi_region_te multi_src_as_te].freeze

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
      unless ALLOWED_USECASES.include?(@usecase[:name])
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

    # rubocop:disable Metrics/AbcSize

    # @return [Integer] source ASN
    # @raise [StandardError] ASN mismatch
    def select_source_asn
      # prioritize ASN in params, ignore ASN in phase_candidate_opts if defined
      return @usecase[:params][:source_as][:asn].to_i if @usecase[:params].key?(:source_as)

      # for source_ases case (multi_src_as_te usecase)
      if @usecase[:phase_candidate_opts].key?(:peer_asn)
        asn = @usecase[:phase_candidate_opts][:peer_asn].to_i
        found_source_as_params = @usecase[:params][:source_ases].find { |source_as| source_as[:asn].to_i == asn }
        return found_source_as_params[:asn] if found_source_as_params

        warn "# DEBUG: params: #{@usecase[:params].inspect}"
        warn "# DEBUG: phase_candidate_opts: #{@usecase[:phase_candidate_opts].inspect}"
        raise StandardError, "ASN:#{asn} mismatch in params and phase_candidate_opts"
      end

      raise StandardError, 'Target ASN not found in phase_candidate_opts'
    end
    # rubocop:enable Metrics/AbcSize
  end
end
