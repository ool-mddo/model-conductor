# frozen_string_literal: true

require 'lib/api/rest_api_base'
require 'lib/policy_manipulation/bgp_policy_patcher'
require 'lib/policy_manipulation/firewall_policy_patcher'

module ModelConductor
  module ApiRoute
    # api policies
    class Policies < RestApiBase
      desc 'Push node policies in a layer'
      params do
        requires :node, type: Array, desc: 'Patch data to overwrite'
      end
      post 'policies' do
        network, snapshot, layer, node_patches = %i[network snapshot layer node].map { |key| params[key] }
        warn "patch policies: nw=#{network}, ss=#{snapshot}, layer=#{layer}"

        # NOTE: Currently, the POST policies API can only be executed at the bgp_proc layer.
        error!("Layer:#{layer} is not layer3 or bgp_proc", 500) unless %w[layer3 bgp_proc].include?(layer)

        # TODO: At this time, it insert json-based objects directly,
        #   but it must be converted Netomox::Topology object to operate/verify data.

        # NOTE: fetch json data (json-hash object), NOT Netomox::Topology object
        topology_data = rest_api.fetch_topology_data(network, snapshot)

        model_patcher = if layer == 'bgp_proc'
                          BgpPolicyPatcher.new(topology_data)
                        elsif layer == 'layer3'
                          FirewallPolicyPatcher.new(topology_data)
                        else
                          error!("Topology:#{network}/#{snapshot} is not found", 404)
                        end
        patched_topology_data = model_patcher.patch_nodes(layer, node_patches)
        error!(patched_topology_data[:message], patched_topology_data[:error]) if patched_topology_data.key?(:error)

        # overwrite (response)
        rest_api.post_topology_data(network, snapshot, patched_topology_data)
      end
    end
  end
end
