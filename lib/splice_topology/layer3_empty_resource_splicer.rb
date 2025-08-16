# frozen_string_literal: true

require 'netomox'

module ModelConductor
  # Splice layer3 empty resources into specified network/snapshot topology
  class Layer3EmptyResourceSplicer
    # @param [Hash] topology_data Topology data to splice
    # @param [Hash] l3e_topology_data Topology data of layer3 empty resources (RFC8345 Hash)
    def initialize(topology_data, l3e_topology_data)
      # convert RFC8345 Hash to Netomox::Topology::Networks
      @topology = instantiate_topology_data(topology_data)
      @l3e_topology = instantiate_topology_data(l3e_topology_data)
    end

    # @return [Hash] spliced topology data
    def to_data
      @topology.to_data
    end

    # @return [void]
    def splice!
      # NOTE: rewrite @topology
      splice_layer3!
    end

    private

    # @param [Hash] topology_data RFC8345 topology data
    # @return [Netomox::Topology::Networks] topology object
    def instantiate_topology_data(topology_data)
      Netomox::Topology::Networks.new(topology_data)
    end

    # @param [Netomox::PseudoDSL::PNode] layer3_target_node Target l3 node
    # @param [Netomox::PseudoDSL::PNode] layer3e_node Empty L3 node (duplicated)
    # @param [Netomox::PseudoDSL::PTermPoint] layer3e_tp Empty L3 tp (in layer3e_node)
    def add_empty_tp_for_dup_node(layer3_target_node, layer3e_node, layer3e_tp)
      layer3_dup_tp = layer3_target_node.find_tp_by_name(layer3e_tp.name)
      unless layer3_dup_tp.nil?
        raise StandardError, "Found duplicate empty resource: #{layer3e_node.name}[#{layer3e_tp.name}]"
      end

      # not found = new tp, append whole term-point
      layer3_target_node.termination_points.push(layer3e_tp)
    end

    # @param [Netomox::PseudoDSL::PNetwork] layer3_nw Target layer3 network
    # @param [Netomox::PseudoDSL::PNetwork] layer3e_nw layer3 network of empty resources
    # @return [void]
    def add_empty_node(layer3_nw, layer3e_nw)
      layer3e_nw.nodes.each do |layer3e_node|
        layer3_dup_node = layer3_nw.find_node_by_name(layer3e_node.name)
        if layer3_dup_node.nil?
          # not found = new node, append whole node
          layer3_nw.nodes.push(layer3e_node)
        else
          # found duplicated node, but interface?
          layer3e_node.termination_points.each do |layer3e_tp|
            add_empty_tp_for_dup_node(layer3_dup_node, layer3e_node, layer3e_tp)
          end
        end
      end
    end

    # @param [Netomox::PseudoDSL::PNetwork] layer3_nw Target layer3 network
    # @param [Netomox::PseudoDSL::PNetwork] layer3e_nw layer3 network of empty resources
    # @return [void]
    def add_links_between_empty_resource(layer3_nw, layer3e_nw)
      layer3e_nw.links.each do |layer3e_link|
        layer3_nw.links.push(layer3e_link)
      end
    end

    # raise [StandardError] found duplicated object in layer3 between target topology and empty-resource
    # @return [void]
    def splice_layer3!
      layer3_nw = @topology.find_network('layer3')
      layer3e_nw = @l3e_topology.find_network('layer3')

      add_empty_node(layer3_nw, layer3e_nw)
      add_links_between_empty_resource(layer3_nw, layer3e_nw)
    end
  end
end
