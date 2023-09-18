# frozen_string_literal: true

require 'grape'

module ModelConductor
  module ApiRoute
    # custom type
    class NodePolicy
      attr_reader :node, :policy_name, :policy_body

      # @param [String] node Node name
      # @param [String] policy_name
      # @param [Array, Hash] policy_body
      def initialize(node:, policy_name:, policy_body:)
        @node = node
        @policy_name = policy_name
        @policy_body = policy_body
      end

      # @return [Hash]
      def to_data
        { @policy_name => @policy_body }
      end

      # @param [ActiveSupport::HashWithIndifferentAccess] data Key-value of posted data
      def self.parse(data)
        kv_def = { node: String, policy_name: String, policy_body: Object }
        if kv_def.each_key.all? { |key| data[key.to_s].is_a?(kv_def[key]) }
          new(**data.symbolize_keys)
        else
          Grape::Types::InvalidValue.new('Invalid policy (found unsupported key or value)')
        end
      end
    end

    # api policies
    class Policies < Grape::API
      desc 'Push node policies in a layer'
      # rubocop:disable Style:RedundantArrayConstructor
      params do
        requires :policies, type: Array[NodePolicy], desc: 'node policies'
      end
      # rubocop:enable Style:RedundantArrayConstructor
      post 'policies' do
        network, snapshot, layer, policies = %i[network snapshot layer policies].map { |key| params[key] }

        # NOTE: fetch json data (json-hash object), NOT Netomox::Topology object
        topology_data = rest_api.fetch_topology_data(network, snapshot)
        error!("Topology:#{network}/#{snapshot} is not found", 404) if topology_data.nil?

        # NOTE: Currently, the POST policies API can only be executed at the bgp_proc layer.
        error!("Layer:#{layer} is not have policy", 500) unless layer == 'bgp_proc'

        # TODO: At this time, it insert json-based objects directly,
        #   but it must be converted Netomox::Topology object to operate/verify data.
        networks = topology_data['ietf-network:networks']['network']
        policies.each do |policy|
          target_layer = networks.find { |nw| nw['network-id'] == layer }
          error!("layer:#{layer} is not found in #{network}/#{snapshot}", 404) if target_layer.nil?

          target_node = target_layer['node'].find { |node| node['node-id'] == policy.node }
          error!("Node:#{policy.node} is not found in layer:#{layer}", 500) if target_node.nil?

          target_node['mddo-topology:bgp-proc-node-attributes']['policy'].push(policy.to_data)
        end

        # overwrite (response)
        rest_api.post_topology_data(network, snapshot, topology_data)
      end
    end
  end
end
