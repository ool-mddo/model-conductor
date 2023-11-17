# frozen_string_literal: true

require 'grape'
require 'lib/bgp_manipulation/node_patch'
require 'lib/bgp_manipulation/preferred_detector'

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
        error!("Layer:#{layer} is not bgp-proc", 500) unless layer == 'bgp_proc'

        # TODO: At this time, it insert json-based objects directly,
        #   but it must be converted Netomox::Topology object to operate/verify data.

        # NOTE: fetch json data (json-hash object), NOT Netomox::Topology object
        topology_data = rest_api.fetch_topology_data(network, snapshot)
        error!("Topology:#{network}/#{snapshot} is not found", 404) if topology_data.nil?

        model_patcher = ModelPatcher.new(topology_data)
        patched_topology_data = model_patcher.patch_nodes(layer, node_patches)
        error!(patched_topology_data[:message], patched_topology_data[:error]) if patched_topology_data.key?(:error)

        # overwrite (response)
        rest_api.post_topology_data(network, snapshot, patched_topology_data)
      end

      desc 'Push preferred peer'
      params do
        requires :ext_asn, type: Integer, desc: 'ASN of external-AS'
        requires :node, type: String, desc: 'Node name (internal, L3)'
        requires :interface, type: String, desc: 'Interface name (Internal, L3)'
      end
      post 'preferred_peer' do
        network, snapshot, layer = %i[network snapshot layer].map { |key| params[key] }
        ext_asn, l3_node, l3_intf = %i[ext_asn node interface].map { |key| params[key] }

        # NOTE: Currently, the POST policies API can only be executed at the bgp_proc layer.
        error!("Layer:#{layer} is not have policy", 500) unless layer == 'bgp_proc'

        # TODO: At this time, use json-based objects directly,
        #   because bgp-policies is cannot convert Topology object (NOT implemented yet)

        topology_data = rest_api.fetch_topology_data(network, snapshot)
        error!("Topology:#{network}/#{snapshot} is not found", 404) if topology_data.nil?

        preferred_detector = PreferredDetector.new(topology_data)
        patched_topology_data = preferred_detector.detect_preferred_peer(layer, ext_asn, l3_node, l3_intf)
        error!(patched_topology_data[:message], patched_topology_data[:error]) if patched_topology_data.key?(:error)

        # overwrite (response)
        rest_api.post_topology_data(network, snapshot, patched_topology_data)
      end
    end
  end
end
