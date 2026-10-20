# frozen_string_literal: true

require_relative '../../lib/generate_conduit_topology/blueprint_network'
require_relative '../../lib/generate_conduit_topology/layer3_conduit_builder'

# helpers for fhrp (VRRP/HSRP) conduit specs
module FhrpConduitHelpers
  TP_KEY = 'ietf-network-topology:termination-point'
  L3_TP_ATTR = 'mddo-topology:l3-termination-point-attributes'

  # @return [String] term-point key in RFC8345 data
  def tp_key
    TP_KEY
  end

  # @return [String] layer3 term-point attribute key
  def l3_attr
    L3_TP_ATTR
  end

  # @return [Hash] original layer3 network (spec/fixtures/layer3_fhrp_topology.json). a copy for each call
  def fhrp_layer3
    load_fixture('layer3_fhrp_topology.json').dig('ietf-network:networks', 'network', 0)
  end

  # @param layer3 [Hash] layer3 network
  # @param node_name [String]
  # @param tp_name [String]
  # @return [Hash] term-point data
  def find_tp(layer3, node_name, tp_name)
    node = layer3['node'].find { |n| n['node-id'] == node_name }
    node[TP_KEY].find { |tp| tp['tp-id'] == tp_name }
  end

  # @return [Hash] fhrp config of the term-point (first one)
  def fhrp_of(layer3, node_name, tp_name)
    find_tp(layer3, node_name, tp_name).dig(L3_TP_ATTR, 'fhrp')&.first
  end

  # @param groups [Hash{String => Array<String>}] { conduit_node_name => [original node names] }
  # @return [ModelConductor::BlueprintNetwork]
  def blueprint_of(groups)
    nodes = groups.map do |name, supports|
      { 'node-id' => name, 'supports' => supports.map { |s| { 'network-ref' => 'layer3', 'node-ref' => s } } }
    end
    network = { 'network-id' => 'bp', 'node' => nodes }
    ModelConductor::BlueprintNetwork.new(network, [network])
  end

  # @return [Array(Hash, Hash, Hash)] [conduit_layer3, node_mapping, tp_mapping]
  def build_conduit(layer3, groups)
    ModelConductor::Layer3ConduitBuilder.new(layer3, blueprint_of(groups)).build
  end

  # blueprint patterns
  def separate_groups
    { 'c_cr1' => ['cr1'], 'c_cr2' => ['cr2'], 'c_cr3' => ['cr3'], 'fw1' => ['fw1'] }
  end

  def collapsed_groups
    { 'c_cr' => %w[cr1 cr2 cr3], 'fw1' => ['fw1'] }
  end

  # @return [Hash] conduit node of the layer3 network
  def conduit_node(conduit_layer3, node_name)
    conduit_layer3['node'].find { |n| n['node-id'] == node_name }
  end

  # @return [Array<String>] term-point names of the conduit node
  def conduit_tp_names(conduit_layer3, node_name)
    conduit_node(conduit_layer3, node_name)[TP_KEY].map { |tp| tp['tp-id'] }
  end
end

RSpec.configure do |config|
  config.include FhrpConduitHelpers
end
