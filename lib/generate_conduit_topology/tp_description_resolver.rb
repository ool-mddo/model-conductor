# frozen_string_literal: true

module ModelConductor
  # Sets `description` of layer3 term-points of a conduit topology from its link structure.
  # The description is "to_<facing node>_<facing tp>" (names in the conduit topology).
  #   - Term-point of a node (router/firewall) on a point-to-point segment (2 endpoints):
  #       the facing endpoint, skipping the segment (same as original topology)
  #   - Term-point of a node on a multi-access segment (3+ endpoints): the facing node is not unique -> no description
  #   - Term-point without link: the facing node was removed by conduit conversion -> no description
  #   - Term-point of a segment node: the node term-point that the segment term-point is linked to
  # Existing descriptions (copied from the original topology) are always discarded.
  #
  # Firewall cluster pair (primary/secondary, see `firewall.pair` node attribute):
  #   the pair shares one (cluster) config, so a term-point with the same name in both nodes is the same interface.
  #   A description determined by a link is copied to the same-name term-point of the partner node
  #   (e.g. ge-7/0/1.0 of the secondary node is linked, ge-7/0/1.0 of the primary node has no link).
  class TpDescriptionResolver
    TP_KEY = 'ietf-network-topology:termination-point'
    L3_TP_ATTR = 'mddo-topology:l3-termination-point-attributes'
    L3_NODE_ATTR = 'mddo-topology:l3-node-attributes'
    DESCRIPTION = 'description'

    # @param nodes [Array<Hash>] conduit layer3 nodes (including segment nodes)
    # @param links [Array<Hash>] conduit layer3 links
    def initialize(nodes, links)
      @nodes = nodes
      @segment_names = nodes.select { |n| segment_node?(n) }.to_set { |n| n['node-id'] }
      @facing = build_facing_table(links)
    end

    # Update term-point attributes of the nodes (destructive)
    # @return [void]
    def apply!
      @nodes.each do |node|
        (node[TP_KEY] || []).each do |tp|
          set_description(tp, description_of(node['node-id'], tp['tp-id']))
        end
      end
      sync_cluster_pairs
    end

    private

    # @return [Hash] { [src_node, src_tp] => [[dst_node, dst_tp], ...] }
    def build_facing_table(links)
      links.each_with_object(Hash.new { |h, k| h[k] = [] }) do |link, table|
        src = link['source']
        dst = link['destination']
        table[[src['source-node'], src['source-tp']]] << [dst['dest-node'], dst['dest-tp']]
      end
    end

    # @return [Array<Array<Hash>>] [[primary_node, secondary_node], ...] firewall cluster pairs in the nodes
    def cluster_pairs
      by_id = @nodes.to_h { |n| [n['node-id'], n] }
      @nodes.filter_map do |node|
        pair = node.dig(L3_NODE_ATTR, 'firewall', 'pair')
        primary = by_id[pair&.dig('primary', 'name')]
        secondary = by_id[pair&.dig('secondary', 'name')]
        [primary, secondary] if primary && secondary && primary.equal?(node)
      end
    end

    def sync_cluster_pairs
      cluster_pairs.each do |primary, secondary|
        secondary_tps = (secondary[TP_KEY] || []).to_h { |tp| [tp['tp-id'], tp] }
        (primary[TP_KEY] || []).each do |tp|
          twin = secondary_tps[tp['tp-id']]
          sync_twin_description(primary['node-id'], tp, twin) if twin
        end
      end
    end

    # copy a description to the twin which has no description (linked <-> unlinked)
    def sync_twin_description(node_name, term_point, twin)
      descr = term_point.dig(L3_TP_ATTR, DESCRIPTION)
      twin_descr = twin.dig(L3_TP_ATTR, DESCRIPTION)
      if twin_descr.nil?
        set_description(twin, descr)
      elsif descr.nil?
        set_description(term_point, twin_descr)
      elsif descr != twin_descr
        ModelConductor.logger.warn "#{node_name}[#{term_point['tp-id']}]: description differs from its cluster pair " \
                                   "(#{descr.inspect} / #{twin_descr.inspect})"
      end
    end

    def segment_node?(node)
      node.dig('mddo-topology:l3-node-attributes', 'node-type') == 'segment'
    end

    # @return [String, nil] description (nil: no description)
    def description_of(node_name, tp_name)
      facing = peer_of(node_name, tp_name)
      facing && "to_#{facing[0]}_#{facing[1]}"
    end

    # @return [Array(String, String), nil] facing [node, tp]
    def peer_of(node_name, tp_name)
      edges = @facing[[node_name, tp_name]]
      return nil if edges.empty?
      return edges.first if @segment_names.include?(node_name)

      across_segment(node_name, tp_name, edges.first)
    end

    # @return [Array(String, String), nil] facing [node, tp] on the other side of the segment
    def across_segment(node_name, tp_name, seg_edge)
      endpoints = segment_endpoints(seg_edge[0])
      if endpoints.size != 2
        ModelConductor.logger.warn "#{node_name}[#{tp_name}]: facing node is not unique (segment #{seg_edge[0]} " \
                                   "has #{endpoints.size} endpoints), description is not set"
        return nil
      end
      endpoints.find { |ep| ep != [node_name, tp_name] }
    end

    # @return [Array<Array>] [[node, tp], ...] endpoints connected to the segment
    def segment_endpoints(segment_name)
      @facing.select { |(node, _tp), _| node == segment_name }.values.flatten(1)
    end

    def set_description(term_point, description)
      # build new hash: attribute hash of the original topology may be shared
      attr = (term_point[L3_TP_ATTR] || {}).reject { |k, _| k == DESCRIPTION }
      attr[DESCRIPTION] = description unless description.nil?
      term_point[L3_TP_ATTR] = attr
    end
  end
end
