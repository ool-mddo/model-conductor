# frozen_string_literal: true

require 'grape'

module ModelConductor
  module ApiRoute
    # api policies
    class Policies < Grape::API
      desc 'Push node policies in a layer'
      # rubocop:disable Style:RedundantArrayConstructor
      params do
        requires :node, type: Array, desc: 'Patch data to overwrite'
      end
      # rubocop:enable Style:RedundantArrayConstructor
      post 'policies' do
        network, snapshot, layer, node_patches = %i[network snapshot layer node].map { |key| params[key] }

        # NOTE: Currently, the POST policies API can only be executed at the bgp_proc layer.
        error!("Layer:#{layer} is not have policy", 500) unless layer == 'bgp_proc'

        # TODO: At this time, it insert json-based objects directly,
        #   but it must be converted Netomox::Topology object to operate/verify data.

        # NOTE: fetch json data (json-hash object), NOT Netomox::Topology object
        topology_data = rest_api.fetch_topology_data(network, snapshot)
        error!("Topology:#{network}/#{snapshot} is not found", 404) if topology_data.nil?

        networks = topology_data['ietf-network:networks']['network']
        layer = networks.find { |nw| nw['network-id'] == layer }
        error!("layer:#{layer} is not found in #{network}/#{snapshot}", 404) if layer.nil?

        node_patches.each do |node_patch|
          target_node = layer['node'].find { |node| node['node-id'] == node_patch['node-id'] }
          error!("Node:#{node_patch['node-id']} is not found in #{layer}", 500) if target_node.nil?

          attr_key = 'mddo-topology:bgp-proc-node-attributes'
          # NOTE: concatenate policies
          target_node[attr_key]['policy'].concat(node_patch[attr_key]['policy'])
        end

        # overwrite (response)
        rest_api.post_topology_data(network, snapshot, topology_data)
      end
    end
  end
end
