# frozen_string_literal: true

require_relative 'router_node_attr_merger'
require_relative 'fhrp_gateway_resolver'
require_relative 'tp_description_resolver'

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
  #     (a group of a single original node (e.g. endpoint) is not collapsed: its TPs keep the original names)
  #     TPs with fhrp (VRRP/HSRP) and not connected to external segments (edge TPs) are kept after the external TPs,
  #     as one TP for each fhrp group (see FhrpGatewayResolver):
  #       redundancy is maintained -> keep fhrp, redundancy is not maintained -> virtual address as ip address
  #   - Segment nodes: auto-generated from external (cross-group) segments only
  #   - TP description ("to_<facing node>_<facing tp>") is regenerated from the conduit links (TpDescriptionResolver)
  class Layer3ConduitBuilder # rubocop:disable Metrics/ClassLength
    TP_KEY = 'ietf-network-topology:termination-point'
    LINK_KEY = 'ietf-network-topology:link'
    L3_NW_ATTR = 'mddo-topology:l3-network-attributes'
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
      external_segs = build_external_segments(node_mapping)
      @fhrp_resolver = build_fhrp_resolver(classified, node_mapping, external_segs)
      external_segs = @fhrp_resolver.collapse_external_endpoints(external_segs)
      tp_mapping = build_tp_mapping(classified, external_segs)
      conduit_layer3 = assemble_conduit_layer3(classified, external_segs, tp_mapping)
      # description depends on the final link structure
      TpDescriptionResolver.new(conduit_layer3['node'], conduit_layer3[LINK_KEY]).apply!
      [conduit_layer3, node_mapping, tp_mapping]
    end

    private

    def build_fhrp_resolver(classified, node_mapping, external_segs)
      router_groups = classified.select { |cg| cg[:type] == :router }.map { |cg| cg[:group] }
      external_tps = external_segs.values.flatten.to_set { |ep| [ep[:node_name], ep[:tp_name]] }
      FhrpGatewayResolver.new(@orig_nodes, node_mapping, router_groups, external_tps)
    end

    def build_external_segments(node_mapping)
      node_to_group = node_mapping.reject { |k, _| segment_name?(k) }
      seg_endpoints = build_segment_endpoints
      external_segs = find_external_segments(seg_endpoints, node_to_group)
      deduplicate_segments(external_segs)
    end

    def assemble_conduit_layer3(classified, external_segs, tp_mapping)
      conduit_nodes = build_conduit_nodes(classified, tp_mapping)
      conduit_seg_nodes = build_conduit_segment_nodes(external_segs, tp_mapping)
      conduit_links = build_conduit_links(external_segs, tp_mapping)
      {
        'network-id' => 'layer3',
        'network-types' => @original_layer3['network-types'],
        L3_NW_ATTR => @original_layer3[L3_NW_ATTR]&.dup,
        'node' => conduit_nodes + conduit_seg_nodes,
        LINK_KEY => conduit_links
      }.compact
    end

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

    # Determine which segments cross group boundaries.
    # Endpoints of nodes not defined in the blueprint are omitted.
    # @return [Hash] { seg_name => [{node_name:, tp_name:, seg_tp:, conduit_name:}] }
    def find_external_segments(seg_endpoints, node_to_group)
      seg_endpoints.each_with_object({}) do |(seg_name, endpoints), external|
        eps = endpoints.filter_map do |ep|
          conduit_name = node_to_group[ep[:node_name]]
          ep.merge(conduit_name:) unless conduit_name.nil?
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
    #   (TPs of a group of a single original node keep the original names, there is no name conflict)
    def build_tp_mapping(classified, external_segs)
      tp_mapping = {}
      eth_counters = Hash.new(0)
      classified.each do |cg|
        if cg[:type] == :firewall
          build_fw_tp_mapping(cg[:group], tp_mapping)
        else
          build_router_tp_mapping(cg[:group], external_segs, tp_mapping, eth_counters)
        end
      end
      tp_mapping
    end

    def build_fw_tp_mapping(group, tp_mapping)
      group.original_node_names.each do |fw_name|
        (find_orig_node(fw_name)[TP_KEY] || []).each do |tp|
          tp_mapping[[fw_name, tp['tp-id']]] = [fw_name, tp['tp-id']]
        end
      end
    end

    def build_router_tp_mapping(group, external_segs, tp_mapping, eth_counters)
      representative = group.original_node_names.first
      ordered_members = [representative] + (group.original_node_names - [representative])
      ordered_members.each do |member_name|
        assign_external_tp_mappings(member_name, group, external_segs, tp_mapping, eth_counters)
      end
      assign_fhrp_edge_tp_mappings(group, tp_mapping, eth_counters)
    end

    # edge TPs which have fhrp are numbered after the external TPs
    def assign_fhrp_edge_tp_mappings(group, tp_mapping, eth_counters)
      @fhrp_resolver.edge_tps(group.conduit_name).each do |edge_tp|
        tp_mapping[[edge_tp.node_name, edge_tp.tp_name]] =
          [group.conduit_name, conduit_tp_name(group, edge_tp.tp_name, eth_counters)]
      end
    end

    def assign_external_tp_mappings(member_name, group, external_segs, tp_mapping, eth_counters)
      external_segs.each_value do |endpoints|
        endpoints.each do |ep|
          next unless ep[:node_name] == member_name

          tp_mapping[[member_name, ep[:tp_name]]] =
            [group.conduit_name, conduit_tp_name(group, ep[:tp_name], eth_counters)]
        end
      end
    end

    # A group of a single original node is not collapsed (no name conflict): keep the original tp name.
    # @return [String] original tp name or next "ethN" of the conduit node
    def conduit_tp_name(group, original_tp_name, eth_counters)
      conduit_name = group.conduit_name
      return original_tp_name if group.original_node_names.size == 1

      eth_counters[conduit_name] += 1
      "eth#{eth_counters[conduit_name]}"
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
      conduit_tp_entries = tp_entries_for_conduit(tp_mapping, conduit_name)
      conduit_tps = conduit_tp_entries.map do |(orig_node_name, orig_tp_name), (_cn, c_tp)|
        build_router_conduit_tp(conduit_name, orig_node_name, orig_tp_name, c_tp)
      end
      {
        'node-id' => conduit_name,
        TP_KEY => conduit_tps,
        L3_NODE_ATTR => merge_router_attrs(group.original_node_names, tp_mapping, conduit_name)
      }
    end

    def tp_entries_for_conduit(tp_mapping, conduit_name)
      tp_mapping
        .select { |(_on, _ot), (cn, _ct)| cn == conduit_name }
        .each_with_index
        .sort_by { |(_k, (_cn, ct)), idx| [ct[/\d+/].to_i, idx] }
        .map(&:first)
    end

    def build_router_conduit_tp(conduit_name, orig_node_name, orig_tp_name, c_tp)
      edge_tp = find_resolved_fhrp_tp(conduit_name, orig_node_name, orig_tp_name)
      if edge_tp
        # edge tp (or collapsed tp on external segment) with fhrp: ip address and fhrp are resolved by fhrp redundancy
        return build_conduit_tp(c_tp, edge_tp.ip_addrs, edge_tp.fhrp)
      end

      orig_node = find_orig_node(orig_node_name)
      orig_tp = (orig_node&.dig(TP_KEY) || []).find { |t| t['tp-id'] == orig_tp_name }
      ip_addrs = orig_tp&.dig(L3_TP_ATTR, 'ip-address') || []
      build_conduit_tp(c_tp, ip_addrs, @fhrp_resolver.maintained_fhrp(orig_node_name, orig_tp_name))
    end

    # @return [FhrpGatewayResolver::EdgeTermPoint, nil] edge tp or collapsed tp on external segment
    def find_resolved_fhrp_tp(conduit_name, orig_node_name, orig_tp_name)
      @fhrp_resolver.find_edge_tp(conduit_name, orig_node_name, orig_tp_name) ||
        @fhrp_resolver.find_collapsed_tp(orig_node_name, orig_tp_name)
    end

    # fhrp is added only if the term-point has it
    def build_conduit_tp(tp_name, ip_addrs, fhrp)
      attribute = { 'ip-address' => ip_addrs, 'flag' => [] }
      attribute['fhrp'] = fhrp unless fhrp.empty?
      { 'tp-id' => tp_name, L3_TP_ATTR => attribute }
    end

    def merge_router_attrs(original_node_names, tp_mapping, conduit_name)
      RouterNodeAttrMerger.new(@orig_nodes).merge(original_node_names, tp_mapping, conduit_name)
    end

    def build_conduit_segment_nodes(external_segs, tp_mapping)
      external_segs.map { |seg_name, endpoints| build_segment_node(seg_name, endpoints, tp_mapping) }
    end

    def build_segment_node(seg_name, endpoints, tp_mapping)
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
  end
end
