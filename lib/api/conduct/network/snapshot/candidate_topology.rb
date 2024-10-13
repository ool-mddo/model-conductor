# frozen_string_literal: true

require 'grape'
require 'lib/generate_candidate_topologies/candidate_topology_generator'

module ModelConductor
  module ApiRoute
    # API to generate candidate topologies
    class CandidateTopology < Grape::API
      namespace 'candidate_topology' do
        desc 'Generate and save several candidate topologies'
        params do
          requires :candidate_number, type: Integer, desc: 'Candidate number', default: 1
          requires :usecase, type: Hash, desc: 'Usecase name and parameters'
        end
        post do
          network, snapshot = %i[network snapshot].map { |key| params[key] }

          # call usecase data fetch api and pass it to candidate topology generator
          #
          # params[:usecase]              => usecase_params
          # {                                {
          #   name: "usecase-name",            name: "usecase_name",
          #   sources: ["src1", "src2"] ...... src1: <(GET /usecases/<usecase_name>/<src1>)
          # }                             :... src2: <(GET /usecases/<usecase_name>/<src2>)
          #                                  }
          usecase_params = { name: params[:usecase][:name] }
          params[:usecase][:sources].each do |source|
            # NOTE: "flows/foo" in sources -> refers as :flow_data
            #   so, if there are several "flows/*" in sources, last one is in operation.
            key = source =~ %r{flows/.+} ? :flow_data : source.to_sym
            usecase_params[key] = rest_api.fetch_usecase_data(usecase_params[:name], network, source)
          end

          # generate candidate topologies
          generator = CandidateTopologyGenerator.new(network, snapshot, usecase_params)
          candidates = generator.generate_candidate_topologies(params[:candidate_number])
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
    end
  end
end
