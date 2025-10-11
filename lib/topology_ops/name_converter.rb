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

    # @param [String] key Key name
    # @param [String] src_node Source node name
    # @param [String] src_tp Source term-point name
    # @param [String] dst_node Destination node name
    # @return [Array(String, String, String)] Converted key names
    # @raise [StandardError] node name not found in convert-table
    def convert_move_targets(key, src_node, src_tp, dst_node)
      [
        convert_node_name(src_node),
        convert_tp_name(src_node, src_tp),
        convert_node_name(dst_node)
      ].map { |h| h[key] }
    end

    # @param [String] src_node Source node name
    # @param [String] src_tp Source term-point name
    # @return [Hash, nil] convert table entry (nil if not found)
    def remove_tp_entry!(src_node, src_tp)
      @ns_convert_table['tp_name_table'][src_node].delete(src_tp)
    end

    # @param [String] dst_node Destination node name
    # @param [Hash] entry_hash term-point convert table ({ tp_name => convert_table_entry(hash) })
    # @return [void]
    def append_tp_entry!(dst_node, entry_hash)
      entry_hash.each do |tp, entry|
        @ns_convert_table['tp_name_table'][dst_node][tp] = entry
      end
    end

    # @param [String] src_node Source node name
    # @param [String] src_tp Source term-point name
    # @param [String] dst_node Destination node name
    # @return [void]
    def move_tp_entry!(src_node, src_tp, dst_node)
      # remove
      entry_src_tp_fwd = remove_tp_entry!(src_node, src_tp)
      src_tp_rev = entry_src_tp_fwd['l3_model']
      entry_src_tp_rev = remove_tp_entry!(src_node, src_tp_rev)

      # append
      append_tp_entry!(dst_node, { src_tp => entry_src_tp_fwd, src_tp_rev => entry_src_tp_rev })
    end

    # @return [Hash] Converted table
    def to_data
      @ns_convert_table
    end
  end
end
