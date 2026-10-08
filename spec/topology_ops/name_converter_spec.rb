# frozen_string_literal: true

require_relative '../../lib/topology_ops/name_converter'

RSpec.describe ModelConductor::NameConverter do
  subject(:converter) { described_class.new(load_fixture('ns_convert_table.json')) }

  describe '#convert_node_name' do
    it 'returns the converted names hash for a known node' do
      result = converter.convert_node_name('router1')
      expect(result).to include('l3_model' => 'router1', 'l1_principal' => 'router1-pe')
    end

    it 'raises StandardError for an unknown node' do
      expect { converter.convert_node_name('unknown_node') }.to raise_error(StandardError, /not found/)
    end
  end

  describe '#convert_tp_name' do
    it 'returns the converted tp names hash for a known node and tp' do
      result = converter.convert_tp_name('router1', 'eth0')
      expect(result).to include('l3_model' => 'eth0', 'l1_principal' => 'ge-0/0/0')
    end

    it 'raises StandardError when the tp is not found' do
      expect { converter.convert_tp_name('router1', 'unknown_tp') }.to raise_error(StandardError, /not found/)
    end
  end

  describe '#remove_tp_entry!' do
    it 'removes and returns the tp entry' do
      entry = converter.remove_tp_entry!('router1', 'eth1')
      expect(entry).to include('l3_model' => 'eth1')
      expect { converter.convert_tp_name('router1', 'eth1') }.to raise_error(StandardError, /not found/)
    end
  end

  describe '#append_tp_entry!' do
    it 'adds a new tp entry for a node' do
      converter.append_tp_entry!('router2', { 'eth1' => { 'l3_model' => 'eth1', 'l1_principal' => 'ge-0/0/1' } })
      result = converter.convert_tp_name('router2', 'eth1')
      expect(result['l1_principal']).to eq('ge-0/0/1')
    end
  end

  describe '#to_data' do
    it 'returns the underlying ns_convert_table hash' do
      data = converter.to_data
      expect(data).to have_key('node_name_table')
      expect(data).to have_key('tp_name_table')
    end
  end
end
