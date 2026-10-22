# frozen_string_literal: true

require 'ipaddr'
require 'json'

module ModelConductor
  # Resolves layer3 term-points which have `fhrp` (VRRP/HSRP) config for a conduit topology.
  #
  # Purpose: the default gateway of endpoints on an edge segment must not be changed by conduit conversion.
  #   - Redundancy is maintained (members of the fhrp group are in two or more conduit nodes):
  #       keep the `fhrp` config.
  #   - Redundancy is not maintained (the members are collapsed into one conduit node, or the others are not
  #       in the blueprint): drop the `fhrp` config, and use the virtual address as the term-point address.
  # Members that are not in the blueprint (not in node_mapping) are ignored.
  #
  # Redundant term-points on an external segment: when the members of a fhrp group are in the same conduit node and
  #   connected to the same external segment (e.g. gateways of endpoints), they are collapsed to one term-point
  #   (the representative, same rule as edge term-points) and the others are removed from the segment.
  #   The address and fhrp of the representative are resolved in the same way as edge term-points.
  #
  # Edge term-point = a term-point of a router group member that has `fhrp` and is not connected to external
  # segment. The edge term-points are collapsed to one term-point per conduit node and fhrp group.
  # The representative is the member that becomes Master/Active:
  #   the highest priority, then the highest source-address (interface address)
  #   (same rule for VRRP (RFC 5798 6.4.3) and HSRP; VRRP priority 255 (address owner) is the highest, 0 is the lowest).
  class FhrpGatewayResolver # rubocop:disable Metrics/ClassLength
    TP_KEY = 'ietf-network-topology:termination-point'
    L3_TP_ATTR = 'mddo-topology:l3-termination-point-attributes'

    # @param fhrp [Hash] fhrp config of a term-point
    # @return [Array] key to identify the fhrp group
    def self.group_key_of(fhrp)
      [fhrp['protocol'], fhrp['group-id'], Array(fhrp['virtual-address']).sort]
    end

    # One fhrp group config of a term-point
    Member = Struct.new(:node_name, :tp_name, :conduit_name, :order, :fhrp, keyword_init: true) do
      # @return [Array] key of fhrp group
      def group_key
        FhrpGatewayResolver.group_key_of(fhrp)
      end
    end

    # Resolved edge term-point
    #   ip_addrs: addresses of the conduit term-point, fhrp: fhrp config of the conduit term-point
    EdgeTermPoint = Struct.new(:node_name, :tp_name, :ip_addrs, :fhrp, keyword_init: true)

    # @param orig_nodes [Array<Hash>] all original layer3 nodes
    # @param node_mapping [Hash] { original_node_name => conduit_node_name } (nodes in the blueprint)
    # @param router_groups [Array<NodeGroup>] router type groups (original_node_names are ordered members)
    # @param external_tps [Set<Array>] Set of [original_node_name, original_tp_name] connected to external segments
    def initialize(orig_nodes, node_mapping, router_groups, external_tps)
      @orig_nodes = orig_nodes.to_h { |n| [n['node-id'], n] }
      @node_mapping = node_mapping
      @router_groups = router_groups
      @external_tps = external_tps
      @members = collect_members
      @redundant_keys = redundant_group_keys
      @edge_tps = resolve_edge_tps
      @collapsed_tps = {}
    end

    # Collapse redundant fhrp term-points of a conduit node on the same external segment into the representative.
    # @param external_segs [Hash] { seg_name => [{node_name:, tp_name:, seg_tp:, conduit_name:}] }
    # @return [Hash] external_segs without the endpoints of the removed term-points
    def collapse_external_endpoints(external_segs)
      representatives = []
      collapsed_segs = external_segs.transform_values do |endpoints|
        removed = collapsed_conduit_groups(endpoints).flat_map do |conduit_endpoints|
          collapse_conduit_endpoints(conduit_endpoints, representatives)
        end
        endpoints.reject { |ep| removed.include?(ep) }
      end
      @collapsed_tps = resolve_collapsed_tps(representatives)
      collapsed_segs
    end

    # @param node_name [String] original node name
    # @param tp_name [String] original term-point name
    # @return [EdgeTermPoint, nil] resolved term-point if it is the representative of collapsed external term-points
    def find_collapsed_tp(node_name, tp_name)
      @collapsed_tps[[node_name, tp_name]]
    end

    # @param conduit_name [String] conduit (router group) node name
    # @return [Array<EdgeTermPoint>] edge term-points to keep in the conduit node (ordered)
    def edge_tps(conduit_name)
      @edge_tps.fetch(conduit_name, [])
    end

    # @param conduit_name [String] conduit (router group) node name
    # @param node_name [String] original node name
    # @param tp_name [String] original term-point name
    # @return [EdgeTermPoint, nil] resolved edge term-point (nil if the term-point is not kept as an edge tp)
    def find_edge_tp(conduit_name, node_name, tp_name)
      edge_tps(conduit_name).find { |tp| tp.node_name == node_name && tp.tp_name == tp_name }
    end

    # fhrp config to carry over to the conduit term-point which is connected to external segment
    # @param node_name [String] original node name
    # @param tp_name [String] original term-point name
    # @return [Array<Hash>] fhrp of the term-point which redundancy is maintained (deep copy)
    def maintained_fhrp(node_name, tp_name)
      fhrp = original_fhrp(node_name, tp_name).select { |f| @redundant_keys.include?(self.class.group_key_of(f)) }
      deep_copy(fhrp)
    end

    private

    def deep_copy(data)
      JSON.parse(JSON.generate(data))
    end

    def original_tps(node_name)
      @orig_nodes.dig(node_name, TP_KEY) || []
    end

    def original_fhrp(node_name, tp_name)
      tp = original_tps(node_name).find { |t| t['tp-id'] == tp_name }
      tp&.dig(L3_TP_ATTR, 'fhrp') || []
    end

    # @return [Array<Array<Hash>>] endpoints of each router conduit node (two or more original nodes) on a segment
    def collapsed_conduit_groups(endpoints)
      router_conduit_names = @router_groups.map(&:conduit_name)
      endpoints.group_by { |ep| ep[:conduit_name] }
               .select { |name, eps| router_conduit_names.include?(name) && eps.uniq { |ep| ep[:node_name] }.size > 1 }
               .values
    end

    # @param endpoints [Array<Hash>] endpoints of a conduit node on a segment
    # @param representatives [Array<Member>] (output) representative members of the collapsed fhrp groups
    # @return [Array<Hash>] endpoints to be removed
    def collapse_conduit_endpoints(endpoints, representatives)
      redundant_member_groups(endpoints).flat_map do |group|
        representative = group.min_by { |member| representative_key(member) }
        representatives << representative
        removed = group.reject { |member| same_tp?(member, representative) }
        removed.filter_map { |member| find_endpoint(endpoints, member) }
      end.uniq
    end

    # @return [Array<Array<Member>>] fhrp groups (members of the endpoints) that have two or more original nodes
    def redundant_member_groups(endpoints)
      members = @members.select { |member| find_endpoint(endpoints, member) }
      members.group_by(&:group_key).values.select { |group| group.map(&:node_name).uniq.size > 1 }
    end

    def find_endpoint(endpoints, member)
      endpoints.find { |ep| ep[:node_name] == member.node_name && ep[:tp_name] == member.tp_name }
    end

    def same_tp?(member, other)
      member.node_name == other.node_name && member.tp_name == other.tp_name
    end

    # @return [Hash] { [original_node_name, original_tp_name] => EdgeTermPoint }
    def resolve_collapsed_tps(representatives)
      representatives.group_by { |member| [member.node_name, member.tp_name] }
                     .to_h { |key, members| [key, build_edge_tp(*key, members)] }
    end

    # member order in the router group (representative node is the first)
    def member_order(node_name)
      @router_groups.each do |group|
        index = group.original_node_names.index(node_name)
        return index unless index.nil?
      end
      0
    end

    # @return [Array<Member>] fhrp group configs of all nodes in the blueprint
    def collect_members
      @node_mapping.flat_map do |node_name, conduit_name|
        original_tps(node_name).flat_map do |tp|
          (tp.dig(L3_TP_ATTR, 'fhrp') || []).map do |fhrp|
            Member.new(node_name:, tp_name: tp['tp-id'], conduit_name:, order: member_order(node_name), fhrp:)
          end
        end
      end
    end

    # @return [Set<Array>] keys of fhrp group that the members are in two or more conduit nodes
    def redundant_group_keys
      @members.group_by(&:group_key)
              .select { |_key, members| members.map(&:conduit_name).uniq.size > 1 }
              .keys.to_set
    end

    # @param address [String] ip address (with prefix length)
    # @return [Integer] number of the address (-1 if invalid) to compare addresses
    def address_number(address)
      IPAddr.new(address.to_s.split('/').first).to_i
    rescue IPAddr::Error
      -1
    end

    # @return [Array] sort key (the first is the representative: Master/Active)
    def representative_key(member)
      [-member.fhrp['priority'].to_i, -address_number(member.fhrp['source-address']), member.order, member.tp_name]
    end

    def edge_member?(member, router_conduit_names)
      router_conduit_names.include?(member.conduit_name) &&
        !@external_tps.include?([member.node_name, member.tp_name]) &&
        @router_groups.any? { |group| group.original_node_names.include?(member.node_name) }
    end

    # @return [Array<Member>] representative member of each (conduit node, fhrp group) in edge term-points
    def representatives
      router_conduit_names = @router_groups.map(&:conduit_name)
      edge_members = @members.select { |member| edge_member?(member, router_conduit_names) }
      edge_members.group_by { |member| [member.conduit_name, member.group_key] }
                  .values.map { |members| members.min_by { |member| representative_key(member) } }
    end

    # @return [Hash] { conduit_name => [EdgeTermPoint] }
    def resolve_edge_tps
      edge_tps = representatives.group_by { |member| [member.node_name, member.tp_name] }
                                .map { |(node_name, tp_name), members| build_edge_tp(node_name, tp_name, members) }
      edge_tps.group_by { |tp| @node_mapping[tp.node_name] }
              .transform_values { |tps| tps.sort_by { |tp| [member_order(tp.node_name), tp.tp_name] } }
    end

    def build_edge_tp(node_name, tp_name, members)
      maintained, lost = members.partition { |member| @redundant_keys.include?(member.group_key) }
      warn_mixed(node_name, tp_name) if !maintained.empty? && !lost.empty?
      if maintained.empty?
        EdgeTermPoint.new(node_name:, tp_name:, ip_addrs: virtual_ip_addrs(node_name, tp_name, lost), fhrp: [])
      else
        EdgeTermPoint.new(node_name:, tp_name:, ip_addrs: original_ip_addrs(node_name, tp_name),
                          fhrp: deep_copy(maintained.map(&:fhrp)))
      end
    end

    def warn_mixed(node_name, tp_name)
      ModelConductor.logger.warn "#{node_name}[#{tp_name}] has fhrp groups with and without redundancy in conduit. " \
                                 'fhrp groups without redundancy are dropped.'
    end

    def original_ip_addrs(node_name, tp_name)
      tp = original_tps(node_name).find { |t| t['tp-id'] == tp_name }
      tp&.dig(L3_TP_ATTR, 'ip-address') || []
    end

    # @return [Array<String>] virtual addresses with prefix length of source-address
    #   (original ip addresses if the virtual addresses can not be converted)
    def virtual_ip_addrs(node_name, tp_name, members)
      addrs = members.flat_map { |member| virtual_addresses_with_prefix(member.fhrp) }.uniq
      return addrs unless addrs.empty?

      ModelConductor.logger.warn "#{node_name}[#{tp_name}]: virtual address of fhrp is not converted (source-address)"
      original_ip_addrs(node_name, tp_name)
    end

    def virtual_addresses_with_prefix(fhrp)
      source_addr, prefix_length = fhrp['source-address'].to_s.split('/')
      return [] if prefix_length.nil?

      source_family = IPAddr.new(source_addr).family
      Array(fhrp['virtual-address']).filter_map do |vip|
        "#{vip}/#{prefix_length}" if IPAddr.new(vip).family == source_family
      end
    rescue IPAddr::Error
      []
    end
  end
end
