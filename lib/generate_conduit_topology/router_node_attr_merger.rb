# frozen_string_literal: true

require 'ipaddr'

module ModelConductor
  # Merges layer3 node attributes for a router conduit node from multiple original nodes.
  # Collects surviving prefixes (those connected to external TPs) and static routes.
  class RouterNodeAttrMerger
    TP_KEY = 'ietf-network-topology:termination-point'
    L3_NODE_ATTR = 'mddo-topology:l3-node-attributes'
    L3_TP_ATTR = 'mddo-topology:l3-termination-point-attributes'

    # @param orig_nodes [Array<Hash>] all original layer3 nodes
    def initialize(orig_nodes)
      @orig_nodes = orig_nodes
    end

    # @param original_node_names [Array<String>]
    # @param tp_mapping [Hash] { [orig_node, orig_tp] => [conduit_node, conduit_tp] }
    # @param conduit_name [String]
    # @return [Hash] merged l3-node-attributes
    def merge(original_node_names, tp_mapping, conduit_name)
      all_prefixes = []
      all_static_routes = []
      original_node_names.each do |node_name|
        collect_node_attrs(node_name, tp_mapping, conduit_name, all_prefixes, all_static_routes)
      end
      { 'node-type' => 'node', 'prefix' => all_prefixes, 'static-route' => all_static_routes, 'flag' => [] }
    end

    private

    def collect_node_attrs(node_name, tp_mapping, conduit_name, all_prefixes, all_static_routes)
      orig_node = @orig_nodes.find { |n| n['node-id'] == node_name }
      attrs = orig_node&.dig(L3_NODE_ATTR) || {}
      surviving_prefixes = node_surviving_prefixes(orig_node, tp_mapping, node_name, conduit_name)
      add_unique_prefixes(all_prefixes, attrs['prefix'] || [], surviving_prefixes)
      add_unique_static_routes(all_static_routes, attrs['static-route'] || [])
    end

    def node_surviving_prefixes(orig_node, tp_mapping, node_name, conduit_name)
      ext_tp_names = external_tp_names_for(tp_mapping, node_name, conduit_name)
      ips = tp_surviving_ips(orig_node, ext_tp_names)
      ips.filter_map { |ip| ip_to_prefix(ip) }
    end

    def external_tp_names_for(tp_mapping, node_name, conduit_name)
      tp_mapping
        .select { |k, v| k.first == node_name && v.first == conduit_name }
        .map { |k, _v| k.last }
    end

    def tp_surviving_ips(orig_node, ext_tp_names)
      (orig_node&.dig(TP_KEY) || [])
        .select { |tp| ext_tp_names.include?(tp['tp-id']) }
        .flat_map { |tp| tp.dig(L3_TP_ATTR, 'ip-address') || [] }
    end

    def add_unique_prefixes(all_prefixes, prefixes, surviving_prefixes)
      prefixes.each do |pfx|
        next unless surviving_prefixes.include?(pfx['prefix'])

        all_prefixes << pfx unless all_prefixes.any? { |p| p['prefix'] == pfx['prefix'] }
      end
    end

    def add_unique_static_routes(all_static_routes, static_routes)
      static_routes.each { |sr| all_static_routes << sr unless all_static_routes.include?(sr) }
    end

    # Convert interface IP (e.g., "172.16.1.2/30") to network prefix ("172.16.1.0/30")
    def ip_to_prefix(ip_with_mask)
      addr, prefix_len = ip_with_mask.split('/')
      "#{IPAddr.new("#{addr}/#{prefix_len}")}/#{prefix_len}"
    rescue StandardError
      nil
    end
  end
end
