# frozen_string_literal: true

require 'grape'

module ModelConductor
  module ApiRoute
    class CandidateTopology < Grape::API
      namespace 'candidate_topology' do
        desc 'Post several candiadte topologies'
        params do
          requires :usecase, type: String, desc: 'Usecase name'
          requires :candidate_number, type: Integer, desc: 'Candidate number', default: 1
        end
        post do
          network, snapshot = %i[network snapshot].map { |key| params[key] }
          base_topology = rest_api.fetch_topology_object(network, snapshot)

          info_list = []
          (1..params[:candidate_number]).each do |candidate_index|
            # TODO: generate candidate_i
            candidate_topology = base_topology.dup
            # save candidate_i topology
            candidate_snapshot_name = "original_candidate_#{candidate_index}"
            rest_api.post_topology_data(network, candidate_snapshot_name, candidate_topology.to_data)
            info_list.push({ network: network, snapshot: candidate_snapshot_name })
          end

          # response
          info_list
        end
      end
    end
  end
end
