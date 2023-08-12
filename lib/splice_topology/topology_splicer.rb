# frozen_string_literal: true

require 'netomox'
require 'ipaddress'
require_relative 'netomox_patch'

module ModelConductor
  # rubocop:disable Metrics/ClassLength

  # Splice external topology data to specified network/snapshot topology
  class TopologySplicer
    # Network names to splicing
    SPLICE_TARGET_NETWORKS = %w[layer3 bgp_proc].freeze

    # @param [Hash] int_topology_data (Internal) topology data (RFC8345 Hash)
    # @param [Hash] ext_topology_data External topology data (RFC8345 Hash)
    def initialize(int_topology_data, ext_topology_data)
      @int_topology = instantiate_topology_data(int_topology_data)
      @ext_topology = instantiate_topology_data(ext_topology_data)
      @over_splice = false
    end

    # @return [Hash] spliced topology data
    def to_data
      @int_topology.to_data
    end

    # @return [void]
    def splice!
      # NOTE: it modify (write) @int_topology
      insert_networks!
      insert_supports!
      splice_bgp_proc!
      splice_layer3!
    end

    private

    # @param [Hash] topology_data RFC8345 topology data
    # @return [Netomox::Topology::Networks] topology object
    def instantiate_topology_data(topology_data)
      Netomox::Topology::Networks.new(topology_data)
    end

    # @param [Netomox::Topology::TpRef, Netomox::Topology::SupportingTerminationPoint] edge Link edge or support-tp
    # @return [Netomox::Topology::TermPoint] supporting term-point (underlay tp instance)
    # @raise [StandardError] unknown network_ref/node_ref
    def find_supported_tp(edge)
      # TpRef and SupportingTerminationPoint owns methods:
      #   #network_ref, #node_ref, #tp_ref (return [String])

      network = @int_topology.find_network(edge.network_ref)
      raise StandardError, "Unknown supporting network: #{edge.network_ref} (edge: #{edge}" if network.nil?

      node = network.find_node_by_name(edge.node_ref)
      raise StandardError, "Unknown supporting node: #{edge.node_ref} (edge: #{edge}" if node.nil?

      term_point = node.find_tp_by_name(edge.tp_ref)
      raise StandardError, "Unknown supporting tp: #{edge.tp_ref} (edge: #{edge}" if term_point.nil?

      term_point
    end

    # @param [Netomox::Topology::TpRef] bgp_as_edge A link-edge in bgp_as layer
    # @return [Netomox::Topology::TermPoint] bgp_proc term-point supported by bgp_as_edge
    def find_supported_bgp_proc_tp(bgp_as_edge)
      # bgp_as
      bgp_as_tp = find_supported_tp(bgp_as_edge)

      # bgp_proc
      bgp_as_support = bgp_as_tp.supports[0] # => Netomox::Topology::SupportingTerminationPoint
      find_supported_tp(bgp_as_support)
    end

    # @param [Netomox::Topology::TpRef] bgp_as_edge A link-edge in bgp_as layer
    # @return [Netomox::Topology::TermPoint] L3 term-point supported by bgp_as_edge
    def find_supported_l3_tp(bgp_as_edge)
      # bgp_proc
      supported_bgp_tp = find_supported_bgp_proc_tp(bgp_as_edge)

      # layer3
      bgp_support = supported_bgp_tp.supports[0] # => Netomox::Topology::SupportingTerminationPoint
      find_supported_tp(bgp_support)
    end

    # @return [void]
    def insert_supports!
      bgp_as_nw = @int_topology.find_network('bgp_as')
      bgp_nw = @int_topology.find_network('bgp_proc')

      bgp_as_nw.nodes.each do |bgp_as_node|
        # external-as-node in bgp_as network have support node (given)
        next unless bgp_as_node.supports.empty?

        # internal-as-node in bgp_as network does not have support node to bgp network
        # TODO: node attribute in bgp_as network is required
        asn = bgp_as_node.name.gsub(/as(\d+)/, '\1').to_i
        bgp_nw.nodes.each do |bgp_node|
          next unless bgp_node.attribute.confederation_id == asn

          bgp_as_node.append_support_by_node(bgp_node)
        end
      end
    end

    # @param [Netomox::Topology::TermPoint] l3_tp Layer3 term-point
    #   (node/endpoint connected with segment node)
    # @return [String] Term-point name of a (L3) segment node (facing term-point of the l3_tp)
    def seg_tp_name(l3_tp)
      "#{l3_tp.parent_name}_#{l3_tp.name}"
    end

    # @param [Netomox::Topology::TermPoint] l3_tp1 L3 term-point1 (src)
    # @param [Netomox::Topology::TermPoint] l3_tp2 L3 term-point2 (dst)
    # @return [String] IP address string of a segment (ex: "a.b.c.d/xx")
    def segment_address_by_tps(l3_tp1, l3_tp2)
      # NOTE: eBGP peer may not have an IP address
      # find a ip-address
      tp_ip = l3_tp1.attribute.ip_addrs&.[](0) || l3_tp2.attribute.ip_addrs&.[](0)
      seg_ip = IPAddress(tp_ip)
      "#{seg_ip.network}/#{seg_ip.prefix}"
    end

    # @param [Netomox::Topology::Network] int_bgp_proc_nw Internal bgp_proc network (layer)
    # @param [Netomox::Topology::TermPoint] src_bgp_proc_tp Source bgp_proc term-point
    # @param [Netomox::Topology::TermPoint] dst_bgp_proc_tp Destination bgp_proc term-point
    def append_bgp_proc_link_between(int_bgp_proc_nw, src_bgp_proc_tp, dst_bgp_proc_tp)
      # append a link (unidirectional)
      int_bgp_proc_nw.append_link_by_tp(src_bgp_proc_tp, dst_bgp_proc_tp)
    end

    # @param [Netomox::Topology::Network] int_l3_nw Internal L3 network (layer)
    # @param [Netomox::Topology::TermPoint] src_l3_tp Source L3 term-point
    # @param [Netomox::Topology::TermPoint] dst_l3_tp Destination L3 term-point
    # @return [void]
    def append_l3_link_between(int_l3_nw, src_l3_tp, dst_l3_tp)
      seg_addr = segment_address_by_tps(src_l3_tp, dst_l3_tp)
      l3_seg_node = int_l3_nw.append_segment_node(seg_addr, src_l3_tp, dst_l3_tp)
      src_l3_seg_tp = l3_seg_node.find_tp_by_name(seg_tp_name(src_l3_tp))
      dst_l3_seg_tp = l3_seg_node.find_tp_by_name(seg_tp_name(dst_l3_tp))

      # append links (unidirectional)
      int_l3_nw.append_link_by_tp(src_l3_tp, src_l3_seg_tp) # src -> seg
      int_l3_nw.append_link_by_tp(dst_l3_seg_tp, dst_l3_tp) #        seg -> dst
    end

    # @param [String] nw_name Network (layer) name to splice
    # @return [void]
    # @yield [bgp_as_link, int_nw] Operation to connect int/ext link
    # @yieldparam [Netomox::Topology::Link] bgp_as_link A link in bgp_as layer
    # @yieldparam [Netomox::Topology::Network] int_nw Target (internal) network (specified by nw_name)
    # @yieldreturn [void]
    def splice_network!(nw_name)
      # NOTE: Prevent the same data added multiple times by repeatedly executing without initialization.
      return if @over_splice

      int_nw = @int_topology.find_network(nw_name)
      ext_nw = @ext_topology.find_network(nw_name)

      # NOTE: modify (write) internal topology data
      # insert nodes in external network to internal network
      int_nw.nodes.concat(ext_nw.nodes)
      # insert links in external network to internal network
      int_nw.links.concat(ext_nw.links)

      # splice int/ext AS according to BGP-AS topology
      bgp_as_nw = @ext_topology.find_network('bgp_as')
      bgp_as_nw.links.each do |bgp_as_link|
        yield(bgp_as_link, int_nw)
      end
    end

    # Splice both bgp_proc of ext- and int- topology data
    # @return [void]
    def splice_bgp_proc!
      splice_network!('bgp_proc') do |bgp_as_link, int_bgp_proc_nw|
        src_bgp_proc_tp = find_supported_bgp_proc_tp(bgp_as_link.source)
        dst_bgp_proc_tp = find_supported_bgp_proc_tp(bgp_as_link.destination)
        # uni-directional: a link between term-points in bgp-as topology is bidirectional
        append_bgp_proc_link_between(int_bgp_proc_nw, src_bgp_proc_tp, dst_bgp_proc_tp)
      end
    end

    # Splice both layer3 of ext- and int- topology data
    # @return [void]
    def splice_layer3!
      splice_network!('layer3') do |bgp_as_link, int_l3_nw|
        src_l3_tp = find_supported_l3_tp(bgp_as_link.source)
        dst_l3_tp = find_supported_l3_tp(bgp_as_link.destination)
        # uni-direction: a link between term-points in bgp-as topology is bidirectional
        append_l3_link_between(int_l3_nw, src_l3_tp, dst_l3_tp)
      end
    end

    # Insert networks (layers) in external topology data into internal topology data
    # @return [void]
    def insert_networks!
      # NOTE: without splicing target network, modify (write) internal topology data
      @ext_topology.networks.reject { |nw| SPLICE_TARGET_NETWORKS.include?(nw.name) }.each do |ext_network|
        if @int_topology.find_network(ext_network.name)
          ModelConductor.logger.warn "Conflict network(layer) in int/ext network: #{ext_network.name}, ignore it."
          @over_splice = true
          next
        end

        @int_topology.networks.unshift(ext_network)
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
