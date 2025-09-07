# frozen_string_literal: true

module ModelConductor
  # convert host/interface name (namespace converters)
  class NameConverter
    # @param [Hash] ns_convert_table Namespace convert table
    def initialize(ns_convert_table)
      @ns_convert_table = ns_convert_table

      # aliases
      @node_name_table = ns_convert_table['node_name_table']
      @tp_name_table = ns_convert_table['tp_name_table']
    end

    # @param [String] node_name Host name
    # @return [Hash] Converted host name (nil if not found)
    # @raise [StandardError] node name not found in convert-table
    def convert_node_name(node_name)
      converted = @node_name_table[node_name]
      raise StandardError, "node name not found in convert-table: #{node_name}" if converted.nil?

      converted
    end

    # @param [String] tp_name Term-point name
    # @return [Hash] Converted term-point name (nil if not found)
    # @raise [StandardError] tp name not found in convert-table
    def convert_tp_name(node_name, tp_name)
      converted = @tp_name_table[node_name][tp_name]
      raise StandardError, "tp name not found in convert-table: #{tp_name}" if converted.nil?

      converted
    end

    # @return [Hash] Converted table
    def to_data
      @ns_convert_table
    end
  end
end
