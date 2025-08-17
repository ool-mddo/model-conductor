# frozen_string_literal: true

require 'netomox'

module ModelConductor
  # Link endpoint data of topology-ops args
  class ArgLinkEndpoint
    # @attribute [rw] node Node name
    #   @return [String]
    # @!attribute [rw] tp Term-point name
    #   @return [String]
    attr_accessor :node, :tp

    # @param [String] node Node name
    # @param [String] term_point Term-point name
    def initialize(node, term_point)
      @node = node
      @tp = term_point
    end

    # @return [Netomox::Topology::TpRef]
    def to_tpref
      data = { 'source-node' => @node, 'source-tp' => @tp }
      Netomox::Topology::TpRef.new(data, 'layer3')
    end

    # @return [Hash] Hash data
    def to_data
      { 'node' => @node, 'tp' => @tp }
    end

    # @return [String]
    def to_s
      "#{@node},#{@tp}"
    end
  end

  # Link data of topology-ops args
  class ArgLink
    # @!attribute [rw] source
    #   @return [ArgLinkEndpoint]
    # @!attribute [rw] destination
    #   @return [ArgLinkEndpoint]
    attr_accessor :source, :destination

    # @param [Hash] source Source endpoint data
    # @param [Hash] destination Destination endpoint data
    def initialize(source, destination)
      @source = ArgLinkEndpoint.new(source['node'], source['tp'])
      @destination = ArgLinkEndpoint.new(destination['node'], destination['tp'])
    end

    # another constructor
    # @param [Hash] link Link data
    # @return [ArgLink]
    def self.from_link(link)
      new(link['source'], link['destination'])
    end

    # another constructor
    # @param [ArgLinkEndpoint] source Source endpoint
    # @param [ArgLinkEndpoint] destination Destination endpoint
    # @return [ArgLink]
    def self.from_endpoints(source, destination)
      new(source.to_data, destination.to_data)
    end

    # @return [Hash] Hash data
    def to_data
      { 'source' => @source.to_data, 'destination' => @destination.to_data }
    end

    # @return [String]
    def to_s
      [@source, @destination].map(&:to_s).join(' <-> ')
    end
  end
end
