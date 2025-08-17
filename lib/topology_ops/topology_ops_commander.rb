# frozen_string_literal: true

require 'netomox'
require_relative 'arg_link'
require_relative 'name_converter'
require_relative 'netomox_patch'

module ModelConductor
  # command generator for manual topology operation
  class TopologyOpsCommander
    # @param [String] command Command name
    # @param [Hash] command_args Command arguments
    # @param [Hash] topology_data Topology data
    # @param [Hash] ns_convert_table Namespace convert table
    def initialize(command, command_args, topology_data, ns_convert_table)
      @command = command
      @arg_link = ArgLink.from_link(command_args['link'])
      @name_converter = NameConverter.new(ns_convert_table)
      @orig_topology = Netomox::Topology::Networks.new(topology_data)
    end

    # @return [Hash] response data
    def answer
      layer3_nw = @orig_topology.find_network('layer3')
      converted_link = @name_converter.convert_arg_link(@arg_link)

      operation = {
        'command' => @command,
        'original_link' => @arg_link,
        'emulated_link' => converted_link.to_data
      }

      current_resource = {
        'links' => [
          layer3_nw.find_all_links_connect(converted_link.source.to_tpref),
          layer3_nw.find_all_links_connect(converted_link.destination.to_tpref)
        ],
        'empty_bridges' => layer3_nw.find_all_empty_bridges
      }

      {
        'operation' => operation,
        'current_resource' => current_resource,
        'tobe' => operate_tobe(layer3_nw, operation, current_resource)
      }
    end

    private

    # @param [Netomox::Topology::Network] layer3_nw Layer3 network
    # @param [Hash] operation Operation data
    # @param [Hash] current_resource Current resource data
    # @return [Hash]
    def operate_tobe(layer3_nw, operation, current_resource)

    end
  end
end
