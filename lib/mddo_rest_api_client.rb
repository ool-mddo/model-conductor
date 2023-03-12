# frozen_string_literal: true

require 'json'
require 'httpclient'

module ModelConductor
  # http client for linkdown simulation
  class MddoRestApiClient
    # Backend API (batfish-wrapper)
    BATFISH_WRAPPER_HOST = ENV.fetch('BATFISH_WRAPPER_HOST', 'batfish-wrapper:5000')
    # Backend API (netomox-exp)
    NETOMOX_EXP_HOST = ENV.fetch('NETOMOX_EXP_HOST', 'netomox-exp:9292')

    # @param [Logger] logger
    def initialize(logger)
      @logger = logger
      @http_client = HTTPClient.new
      @http_client.receive_timeout = 60 * 60 * 4 # 60sec * 60min * 4h
    end

    # @param [String] api_path PATH of REST API
    # @return [HTTP::Message,nil] Reply
    def delete(api_path)
      url = dispatch_url(api_path)
      @logger.info "DELETE: #{url}"
      response = @http_client.delete(url)
      warn "# [ERROR] #{response.status} < GET #{url}" if error_response?(response)
      response
    end

    # @param [String] api_path PATH of REST API
    # @param [Hash] data Data to post
    # @return [HTTP::Message,nil] Reply
    def post(api_path, data = {})
      url = dispatch_url(api_path)

      str_limit = 80
      data_str = data.to_s.length < str_limit ? data.to_s : "#{data.to_s[0, str_limit - 3]}..."
      @logger.info "POST: #{url}, data=#{data_str}"

      header = { 'Content-Type' => 'application/json' }
      body = JSON.generate(data)
      response = @http_client.post(url, body:, header:)
      warn "# [ERROR] #{response.status} < POST #{url}, data=#{data_str}" if error_response?(response)
      response
    end

    # @param [String] api_path PATH of REST API
    # @param [Hash] param GET parameter
    # @return [HTTP::Message,nil] Reply
    def fetch(api_path, param = {})
      url = dispatch_url(api_path)
      @logger.info "GET: #{url}, param=#{param}"
      response = param.empty? ? @http_client.get(url) : @http_client.get(url, query: param)
      warn "# [ERROR] #{response.status} < GET #{url}" if error_response?(response)
      response
    end

    # @param [String] network Network name
    # @param [String] src_snapshot Source snapshot
    # @param [String] dst_snapshot Destination snapshot
    # @return [Hash, nil] Topology diff data
    def fetch_topology_diff(network, src_snapshot, dst_snapshot)
      response = fetch("/topologies/#{network}/snapshot_diff/#{src_snapshot}/#{dst_snapshot}")
      # NOTICE: DO NOT symbolize
      response_data = fetch_response(response, symbolize_names: false)
      response_data['topology_data']
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @return [Hash, nil] topology data
    def fetch_topology_data(network, snapshot)
      response = fetch("/topologies/#{network}/#{snapshot}/topology")
      # NOTICE: DO NOT symbolize
      response_data = fetch_response(response, symbolize_names: false)
      response_data['topology_data']
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @param [Hash] data Data to post,
    #   empty: generate snapshot data from query data,
    #   exist "topology_data": overwrite topology data
    # @return [Hash, nil] topology data
    def post_topology_data(network, snapshot, data = {})
      response = post("/topologies/#{network}/#{snapshot}/topology", data)
      # NOTICE: DO NOT symbolize
      response_data = fetch_response(response, symbolize_names: false)
      response_data['topology_data']
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @return [Hash, nil]
    def post_batfish_query(network, snapshot)
      response = post("/queries/#{network}/#{snapshot}")
      fetch_response(response)
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @param [Hash] data Data to post (options)
    # @return [Array<Hash>, nil] snapshot patterns
    def post_snapshot_patterns(network, snapshot, data = {})
      response = post("/configs/#{network}/#{snapshot}/snapshot_patterns", data)
      fetch_response(response)
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @return [Array<Hash>, nil] snapshot patterns
    def fetch_snapshot_patterns(network, snapshot)
      response = fetch("/configs/#{network}/#{snapshot}/snapshot_patterns")
      fetch_response(response)
    end

    # @return [Array<String>,nil] networks
    def fetch_networks
      response = fetch('/batfish/networks')
      fetch_response(response)
    end

    # @param [String] network Network name
    # @param [Boolean] simulated Enable to get all simulated snapshots
    # @return [Array<String>,nil] snapshots
    def fetch_snapshots(network, simulated: false)
      url = "/batfish/#{network}/snapshots"
      response = simulated ? fetch(url, { 'simulated' => true }) : fetch(url)
      fetch_response(response)
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @return [String,nil] json string
    def fetch_all_interface_list(network, snapshot)
      # - node: str
      #   interface: str
      #   addresses: []
      # - ...
      response = fetch("/batfish/#{network}/#{snapshot}/interfaces")
      fetch_response(response)
    end

    # @param [String] network Network name in batfish
    # @param [String] snapshot Snapshot name in network
    # @param [String] src_node Source-node name
    # @param [String] src_intf Source-interface name
    # @param [String] dst_ip Destination IP address
    # @return [Hash,nil]
    def fetch_traceroute(network, snapshot, src_node, src_intf, dst_ip)
      url = "/batfish/#{network}/#{snapshot}/#{src_node}/traceroute"
      param = { 'interface' => src_intf, 'destination' => dst_ip }

      # network: str
      # snapshot: str
      # result:
      #   - Flow: {}
      #     Traces: []
      #   - ...
      response = fetch(url, param)
      fetch_response(response)
    end

    # @param [Array<Hash>] index_data Netoviz index
    # @return [Object, nil]
    def post_topologies_index(index_data)
      response = post('/topologies/index', { index_data: })
      fetch_response(response)
    end

    private

    # @param [String] api_path PATH of REST API
    # @return [String] url
    def dispatch_url(api_path)
      api_host = api_path =~ %r{^/?topologies/*} ? NETOMOX_EXP_HOST : BATFISH_WRAPPER_HOST
      "http://#{api_host}/#{api_path}"
    end

    # @param [HTTP::Message] response HTTP response
    # @return [Boolean]
    def error_response?(response)
      # Error when status code is not 2xx
      response.status / 100 != 2
    end

    # @param [HTTP::Message] response HTTP response
    # @param [Boolean] symbolize_names Symbolize names of response body (default: true)
    # @return [Object, nil]
    def fetch_response(response, symbolize_names: true)
      error_response?(response) ? nil : JSON.parse(response.body, { symbolize_names: })
    end
  end
end
