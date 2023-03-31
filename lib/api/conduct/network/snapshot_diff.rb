# frozen_string_literal: true

require 'grape'

module ModelConductor
  module ApiRoute
    # namespace /snapshot_diff
    class SnapshotDiff < Grape::API
      params do
        requires :src_ss, type: String, desc: 'Source snapshot name'
        requires :dst_ss, type: String, desc: 'Destination snapshot name'
        optional :upper_layer3, type: Boolean, desc: 'Diff with layers upper layer3', default: false
      end
      resource 'snapshot_diff/:src_ss/:dst_ss' do
        desc 'Get topology diff'
        get do
          network, src_ss, dst_ss, upl3 = %i[network src_ss dst_ss upper_layer3].map { |key| params[key] }
          # response
          rest_api.fetch_topology_diff(network, src_ss, dst_ss, upper_layer3: upl3)
        end

        desc 'Get topology diff and post (overwrite) to destination snapshot'
        post do
          network, src_ss, dst_ss, upl3 = %i[network src_ss dst_ss upper_layer3].map { |key| params[key] }
          topology_diff = rest_api.fetch_topology_diff(network, src_ss, dst_ss, upper_layer3: upl3)
          rest_api.post_topology_data(network, dst_ss, topology_diff)
          # response
          {}
        end
      end
    end
  end
end
