# frozen_string_literal: true

require_relative 'arg_link'

module ModelConductor
  # convert host/interface name (namespace converters)
  class NameConverter
    # @param [Hash] ns_convert_table Namespace convert table
    def initialize(ns_convert_table)
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

    # @param [ArgLinkEndpoint] endpoint Endpoint data in original namespace
    # @return [ArgLinkEndpoint] converted endpoint data
    def convert_arg_endpoint(endpoint)
      node_entry = convert_node_name(endpoint.node)
      tp_entry = convert_tp_name(endpoint.node, endpoint.tp)
      ArgLinkEndpoint.from_convert_entry(node_entry, tp_entry)
    rescue StandardError => e
      raise StandardError, e.message
    end

    # @param [ArgLink] link Link data in original namespace
    # @return [ArgLink] converted link data
    def convert_arg_link(link)
      src_ep = convert_arg_endpoint(link.source)
      dst_ep = convert_arg_endpoint(link.destination)
      ArgLink.from_endpoints(src_ep, dst_ep)
    end
  end
end
