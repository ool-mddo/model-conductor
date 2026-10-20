# frozen_string_literal: true

require 'rack/test'
require_relative '../../app'

RSpec.describe 'POST /conduct/:network/ns_convert/:src_ss/:dst_ss' do
  include Rack::Test::Methods

  include_context 'with mocked rest_api'

  def app
    ModelConductor::ModelConductorRestApi
  end

  let(:network) { 'mddo-fw' }
  let(:topology) { { 'ietf-network:networks' => { 'network' => [] } } }
  let(:converted_topology) { { 'converted' => true } }
  let(:src_table) { JSON.parse(File.read(File.join(__dir__, '../fixtures/ns_convert_table.json'))) }
  let(:origin_table) { src_table.merge('regenerated' => {}) }

  def post_ns_convert(src_ss, dst_ss, body = {})
    post "/conduct/#{network}/ns_convert/#{src_ss}/#{dst_ss}", body.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  before do
    allow(mock_rest_api).to receive(:fetch_topology_data).and_return(topology)
    allow(mock_rest_api).to receive(:fetch_converted_topology_data).and_return(converted_topology)
    allow(mock_rest_api).to receive(:post_topology_data)
    allow(mock_rest_api).to receive(:post_update_ns_convert_table)
  end

  context 'with table_origin (original -> emulated)' do
    before do
      allow(mock_rest_api).to receive(:post_init_ns_convert_table)
      allow(mock_rest_api).to receive(:fetch_ns_convert_table).with(network, 'original_asis').and_return(origin_table)
    end

    it 'initializes the table in origin snapshot and copies it to the destination snapshot' do
      post_ns_convert('original_asis', 'emulated_asis', table_origin: 'original_asis', usecase: 'refocus_topology')

      expect(last_response.status).to eq 201
      expect(mock_rest_api).to have_received(:post_init_ns_convert_table)
        .with(network, 'original_asis', 'refocus_topology').ordered
      expect(mock_rest_api).to have_received(:post_topology_data)
        .with(network, 'emulated_asis', converted_topology)
      expect(mock_rest_api).to have_received(:post_update_ns_convert_table)
        .with(network, 'emulated_asis', origin_table)
    end

    it 'copies the table of table_origin even if it differs from src_ss' do
      allow(mock_rest_api).to receive(:fetch_ns_convert_table).with(network, 'other_origin').and_return(origin_table)

      post_ns_convert('original_asis', 'emulated_asis', table_origin: 'other_origin')

      expect(mock_rest_api).to have_received(:fetch_ns_convert_table).with(network, 'other_origin')
      expect(mock_rest_api).to have_received(:post_update_ns_convert_table)
        .with(network, 'emulated_asis', origin_table)
    end
  end

  context 'without table_origin (e.g. emulated -> original)' do
    before do
      allow(mock_rest_api).to receive(:fetch_ns_convert_table).with(network, 'emulated_tobe').and_return(src_table)
    end

    it 'copies the existing source table to the destination snapshot' do
      post_ns_convert('emulated_tobe', 'original_tobe')

      expect(last_response.status).to eq 201
      expect(mock_rest_api).to have_received(:post_update_ns_convert_table)
        .with(network, 'original_tobe', src_table)
    end

    it 'returns 404 and saves nothing when the source table does not exist' do
      allow(mock_rest_api).to receive(:fetch_ns_convert_table).with(network, 'emulated_tobe').and_return(nil)

      post_ns_convert('emulated_tobe', 'original_tobe')

      expect(last_response.status).to eq 404
      expect(mock_rest_api).not_to have_received(:post_topology_data)
      expect(mock_rest_api).not_to have_received(:post_update_ns_convert_table)
    end
  end

  it 'returns 404 when the source snapshot does not exist' do
    allow(mock_rest_api).to receive(:fetch_topology_data).and_return(nil)

    post_ns_convert('original_asis', 'emulated_asis')

    expect(last_response.status).to eq 404
    expect(mock_rest_api).not_to have_received(:post_update_ns_convert_table)
  end
end
