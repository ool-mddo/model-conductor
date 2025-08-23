# frozen_string_literal: true

require_relative 'netomox_patch'
require_relative 'name_converter'

module ModelConductor
  # base class for operation commander
  class OpsCommanderBase
    # @param [String] command Command name
    # @param [Hash] topology_data Topology data (original namespace)
    # @param [Hash] ns_convert_table Namespace convert table
    def initialize(command, topology_data, ns_convert_table)
      @command = command
      @name_converter = NameConverter.new(ns_convert_table)
      original_topology = Netomox::Topology::Networks.new(topology_data)
      @orig_l3nw = original_topology.find_network('layer3')
    end

    def answer
      raise NotImplementedError, 'must be implemented in subclass'
    end
  end
end
