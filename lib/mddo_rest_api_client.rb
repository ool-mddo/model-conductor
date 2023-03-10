# frozen_string_literal: true

require 'json'
require 'httpclient'

module ModelConductor
  # http client for linkdown simulation
  class MddoRestApiClient
    BATFISH_WRAPPER_HOST = ENV.fetch('BATFISH_WRAPPER_HOST', 'batfish-wrapper:5000')
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
    # @param [String] snapshot Snapshot name
    # @return [Hash, nil] topology data
    def fetch_topology_data(network, snapshot)
      url = "/topologies/#{network}/#{snapshot}/topology"
      response = fetch(url)
      return nil if error_response?(response)

      # NOTICE: DO NOT symbolize
      response_data = JSON.parse(response.body, { symbolize_names: false })
      response_data['topology_data']
    end

    # @param [String] network Network name
    # @param [String] snapshot Snapshot name
    # @return [Array<Hash>, nil] snapshot patterns
    def fetch_snapshot_patterns(network, snapshot)
      url = "/configs/#{network}/#{snapshot}/snapshot_patterns"
      response = fetch(url)
      return {} if error_response?(response)

      JSON.parse(response.body, { symbolize_names: true })
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
      response.status % 100 == 2
    end
  end
end
