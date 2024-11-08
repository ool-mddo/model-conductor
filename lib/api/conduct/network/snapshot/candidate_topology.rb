# frozen_string_literal: true

require 'grape'
require 'lib/generate_candidate_topologies/candidate_topology_generator'

module ModelConductor
  module ApiRoute
    # API to generate candidate topologies
    class CandidateTopology < Grape::API
      # rubocop:disable Metrics/BlockLength
      namespace 'candidate_topology' do
        desc 'Generate and save several candidate topologies'
        params do
          requires :phase_number, type: Integer, desc: 'Phase number', default: 1
          requires :candidate_number, type: Integer, desc: 'Candidate number', default: 1
          requires :usecase, type: Hash, desc: 'Usecase name and parameters'
        end
        post do
          network, snapshot, usecase_data = %i[network snapshot usecase].map { |key| params[key] }

          # call usecase data fetch api and pass it to candidate topology generator
          #
          # params[:usecase]              => usecase_params
          # {                                {
          #   name: "usecase-name",            name: "usecase_name",
          #   sources: ["src1", "src2"] ...... src1: <(GET /usecases/<usecase_name>/<src1>)
          # }                             :... src2: <(GET /usecases/<usecase_name>/<src2>)
          #                                  }
          usecase_params = { name: usecase_data[:name] }
          usecase_data[:sources].each do |source|
            usecase_params[source.to_sym] = rest_api.fetch_usecase_data(usecase_params[:name], network, source)
          end

          # NOTE: for pni_te,multi_region_te usecase, phase_candidate_opts includes flow data option.
          if usecase_params.key?(:phase_candidate_opts) && usecase_params[:phase_candidate_opts].key?(:flow_data)
            source = usecase_params[:phase_candidate_opts][:flow_data]
            usecase_params[:phase_candidate_opts][:flow_data] =
              rest_api.fetch_usecase_data(usecase_params[:name], network, source)
          end

          # generate candidate topologies
          phase_number, candidate_number = %i[phase_number candidate_number].map { |key| params[key] }
          generator = CandidateTopologyGenerator.new(network, snapshot, usecase_params)
          candidates = generator.generate_candidate_topologies(phase_number, candidate_number)
          error!('Error in generate candidate topology', 500) if candidates.nil?

          # save each candidate topology
          candidates.each do |candidate|
            rest_api.post_topology_data(candidate[:network], candidate[:snapshot], candidate[:topology])
          end

          # response
          # ignore topology data (too fat)
          candidates.map! do |candidate|
            candidate.delete(:topology)
            candidate
          end
        end
      end
      # rubocop:enable Metrics/BlockLength
    end
  end
end
