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

          info_list = []
          generator = CandidateTopologyGenerator.new(network, snapshot, params[:usecase])
          (1..params[:candidate_number]).each do |candidate_index|
            candidate_topology = generator.generate_candidate_topologies(candidate_index)
            next if candidate_topology.nil?

            # save candidate_i topology
            candidate_snapshot_name = "original_candidate_#{candidate_index}"
            rest_api.post_topology_data(network, candidate_snapshot_name, candidate_topology.to_data)
            info_list.push({ network:, snapshot: candidate_snapshot_name })
          end

          # response
          info_list
        end
      end
    end
  end
end
