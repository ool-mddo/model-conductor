# frozen_string_literal: true

require 'ipaddr'
require 'set'

module ModelConductor
  # Builds a conduit layer3 topology network from the original layer3 and a blueprint network.
  # Produces:
  #   conduit layer3 network hash (RFC8345),
  #   node_mapping { original_node_name => conduit_node_name },
  #   tp_mapping { [original_node_name, original_tp_name] => [conduit_node_name, conduit_tp_name] }
  #
  # Rules:
  #   - Firewall nodes (flag contains "firewall"): all original nodes preserved, TPs unchanged
  #   - Router nodes: collapsed to one representative node; external TPs renamed eth1, eth2, ...
  #   - Segment nodes: auto-generated from external (cross-group) segments only
  class Layer3ConduitBuilder
    TP_KEY = 'ietf-network-topology:termination-point'
    LINK_KEY = 'ietf-network-topology:link'
    L3_NODE_ATTR = 'mddo-topology:l3-node-attributes'
    L3_TP_ATTR = 'mddo-topology:l3-termination-point-attributes'

    # @param original_layer3 [Hash] 'layer3' network data from original topology
    # @param blueprint_network [BlueprintNetwork]
    def initialize(original_layer3, blueprint_network)
      @original_layer3 = original_layer3
      @blueprint_network = blueprint_network
      @orig_nodes = original_layer3['node'] || []
      @orig_links = original_layer3[LINK_KEY] || []
    end

    # @return [Array(Hash, Hash, Hash)] [conduit_layer3, node_mapping, tp_mapping]
    def build
      classified = classify_node_groups
      node_mapping = build_node_mapping(classified)
      node_to_group = node_mapping.reject { |k, _| segment_name?(k) }

      seg_endpoints = build_segment_endpoints
      external_segs = find_external_segments(seg_endpoints, node_to_group)
      # Deduplicate before TP assignment: keep only the first segment per conduit endpoint pair
      external_segs = deduplicate_segments(external_segs)
      tp_mapping = build_tp_mapping(classified, external_segs)

      conduit_nodes = build_conduit_nodes(classified, tp_mapping)
      conduit_seg_nodes = build_conduit_segment_nodes(external_segs, tp_mapping)
      conduit_links = build_conduit_links(external_segs, tp_mapping)

      conduit_layer3 = {
        'network-id' => 'layer3',
        'network-types' => @original_layer3['network-types'],
        'node' => conduit_nodes + conduit_seg_nodes,
        LINK_KEY => conduit_links
      }.compact

      [conduit_layer3, node_mapping, tp_mapping]
    end

    private

    # @return [Array<Hash>] [{group: NodeGroup, type: :firewall|:router}]
    def classify_node_groups
      @blueprint_network.node_groups.map do |group|
        types = group.original_node_names.map { |name| node_type(name) }
        type = types.include?(:firewall) ? :firewall : :router
        { group:, type: }
      end
    end

    def node_type(node_name)
      node = find_orig_node(node_name)
      raise "Original node '#{node_name}' not found in layer3" if node.nil?

      (node['flag'] || []).include?('firewall') ? :firewall : :router
    end

    # @return [Hash] { original_node_name => conduit_node_name }
    def build_node_mapping(classified)
      classified.each_with_object({}) do |cg, mapping|
        cg[:group].original_node_names.each do |orig_name|
          mapping[orig_name] = cg[:type] == :firewall ? orig_name : cg[:group].conduit_name
        end
      end
    end

    # Build segment_name => [{node_name:, tp_name:, seg_tp:}] from links (Seg→node direction only)
    def build_segment_endpoints
      @orig_links.each_with_object({}) do |link, segs|
        src_node = link['source']['source-node']
        src_tp = link['source']['source-tp']
        dst_node = link['destination']['dest-node']
        dst_tp = link['destination']['dest-tp']

        next unless segment_name?(src_node)

        segs[src_node] ||= []
        segs[src_node] << { node_name: dst_node, tp_name: dst_tp, seg_tp: src_tp }
      end
    end

    # Determine which segments cross group boundaries
    # @return [Hash] { seg_name => [{node_name:, tp_name:, seg_tp:, conduit_name:}] }
    def find_external_segments(seg_endpoints, node_to_group)
      seg_endpoints.each_with_object({}) do |(seg_name, endpoints), external|
        eps = endpoints.map do |ep|
          conduit_name = node_to_group[ep[:node_name]]
          raise "Node '#{ep[:node_name]}' not found in any blueprint group" if conduit_name.nil?

          ep.merge(conduit_name:)
        end
        external[seg_name] = eps if eps.map { |e| e[:conduit_name] }.uniq.size > 1
      end
    end

    # Keep only the first segment for each unique conduit endpoint pair.
    # Parallel segments (original nodes in different groups but same two conduit nodes)
    # are collapsed to one representative.
    # @return [Hash] filtered external_segs
    def deduplicate_segments(external_segs)
      seen = Set.new
      external_segs.select do |_seg_name, endpoints|
        sig = endpoints.map { |e| e[:conduit_name] }.uniq.sort.freeze
        seen.add?(sig)
      end
    end

    # Build tp_mapping: [original_node, original_tp] => [conduit_node, conduit_tp]
    # FW TPs: identity mapping for all TPs
    # Router TPs: only external TPs, renamed eth1, eth2, ... (representative node's TPs first)
    def build_tp_mapping(classified, external_segs)
      tp_mapping = {}
      eth_counters = Hash.new(0)

      classified.each do |cg|
        group = cg[:group]
        if cg[:type] == :firewall
          group.original_node_names.each do |fw_name|
            (find_orig_node(fw_name)[TP_KEY] || []).each do |tp|
              tp_mapping[[fw_name, tp['tp-id']]] = [fw_name, tp['tp-id']]
            end
          end
        else
          conduit_name = group.conduit_name
          representative = group.original_node_names.first
          ordered_members = [representative] + (group.original_node_names - [representative])

          ordered_members.each do |member_name|
            external_segs.each_value do |endpoints|
              endpoints.each do |ep|
                next unless ep[:node_name] == member_name

                eth_counters[conduit_name] += 1
                tp_mapping[[member_name, ep[:tp_name]]] = [conduit_name, "eth#{eth_counters[conduit_name]}"]
              end
            end
          end
        end
      end

      tp_mapping
    end

    def build_conduit_nodes(classified, tp_mapping)
      classified.flat_map do |cg|
        if cg[:type] == :firewall
          build_fw_conduit_nodes(cg[:group])
        else
          [build_router_conduit_node(cg[:group], tp_mapping)]
        end
      end
    end

    def build_fw_conduit_nodes(group)
      group.original_node_names.map do |fw_name|
        orig = find_orig_node(fw_name)
        conduit_tps = (orig[TP_KEY] || []).map do |tp|
          { 'tp-id' => tp['tp-id'], L3_TP_ATTR => (tp[L3_TP_ATTR] || {}).dup }
        end
        node = { 'node-id' => fw_name, TP_KEY => conduit_tps, L3_NODE_ATTR => (orig[L3_NODE_ATTR] || {}).dup }
        node['flag'] = orig['flag'].dup if orig['flag']
        node
      end
    end

    def build_router_conduit_node(group, tp_mapping)
      conduit_name = group.conduit_name

      # Collect (orig_node, orig_tp) entries that map to this conduit node, sorted by eth number
      conduit_tp_entries = tp_mapping
        .select { |(_on, _ot), (cn, _ct)| cn == conduit_name }
        .sort_by { |_k, (_cn, ct)| ct[/\d+/].to_i }

      conduit_tps = conduit_tp_entries.map do |(orig_node_name, orig_tp_name), (_cn, c_tp)|
        orig_node = find_orig_node(orig_node_name)
        orig_tp = (orig_node&.dig(TP_KEY) || []).find { |t| t['tp-id'] == orig_tp_name }
        ip_addrs = orig_tp&.dig(L3_TP_ATTR, 'ip-address') || []
        { 'tp-id' => c_tp, L3_TP_ATTR => { 'ip-address' => ip_addrs, 'flag' => [] } }
      end

      {
        'node-id' => conduit_name,
        TP_KEY => conduit_tps,
        L3_NODE_ATTR => merge_router_attrs(group.original_node_names, tp_mapping, conduit_name)
      }
    end

    def merge_router_attrs(original_node_names, tp_mapping, conduit_name)
      all_prefixes = []
      all_static_routes = []

      original_node_names.each do |node_name|
        orig_node = find_orig_node(node_name)
        attrs = orig_node&.dig(L3_NODE_ATTR) || {}

        # Include only prefixes corresponding to surviving (external) TPs
        external_tp_names = tp_mapping
          .select { |k, v| k.first == node_name && v.first == conduit_name }
          .map { |k, _v| k.last }
        surviving_ips = (orig_node&.dig(TP_KEY) || [])
          .select { |tp| external_tp_names.include?(tp['tp-id']) }
          .flat_map { |tp| tp.dig(L3_TP_ATTR, 'ip-address') || [] }
        surviving_prefixes = surviving_ips.filter_map { |ip| ip_to_prefix(ip) }

        (attrs['prefix'] || []).each do |pfx|
          next unless surviving_prefixes.include?(pfx['prefix'])

          all_prefixes << pfx unless all_prefixes.any? { |p| p['prefix'] == pfx['prefix'] }
        end

        (attrs['static-route'] || []).each do |sr|
          all_static_routes << sr unless all_static_routes.include?(sr)
        end
      end

      { 'node-type' => 'node', 'prefix' => all_prefixes, 'static-route' => all_static_routes, 'flag' => [] }
    end

    def build_conduit_segment_nodes(external_segs, tp_mapping)
      external_segs.map do |seg_name, endpoints|
        conduit_tps = endpoints.map do |ep|
          conduit_node, conduit_tp = tp_mapping[[ep[:node_name], ep[:tp_name]]]
          raise "No TP mapping for #{ep[:node_name]}/#{ep[:tp_name]}" unless conduit_tp

          { 'tp-id' => "#{conduit_node}_#{conduit_tp}", L3_TP_ATTR => {} }
        end
        {
          'node-id' => seg_name,
          TP_KEY => conduit_tps,
          L3_NODE_ATTR => { 'node-type' => 'segment', 'prefix' => [], 'flag' => [] }
        }
      end
    end

    def build_conduit_links(external_segs, tp_mapping)
      external_segs.flat_map do |seg_name, endpoints|
        endpoints.flat_map do |ep|
          conduit_node, conduit_tp = tp_mapping[[ep[:node_name], ep[:tp_name]]]
          raise "No TP mapping for #{ep[:node_name]}/#{ep[:tp_name]}" unless conduit_tp

          seg_tp = "#{conduit_node}_#{conduit_tp}"
          [make_link(seg_name, seg_tp, conduit_node, conduit_tp),
           make_link(conduit_node, conduit_tp, seg_name, seg_tp)]
        end
      end
    end

    def make_link(src_node, src_tp, dst_node, dst_tp)
      {
        'link-id' => "#{src_node},#{src_tp},#{dst_node},#{dst_tp}",
        'source' => { 'source-node' => src_node, 'source-tp' => src_tp },
        'destination' => { 'dest-node' => dst_node, 'dest-tp' => dst_tp }
      }
    end

    def find_orig_node(node_name)
      @orig_nodes.find { |n| n['node-id'] == node_name }
    end

    def segment_name?(name)
      name.start_with?('Seg_')
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
