# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# myblog-dispatch (X/Twitter 投稿用マイクロサービス) の POST /tweet を呼び出す。
#
# 設計方針:
# - X 連携はブログ本体が動作するための必須機能ではない (付加機能) ため、
#   TurnstileService や APP_HOST のような起動時 fail-fast (ENV.fetch 必須) は
#   採用しない。DISPATCH_BASE_URL / DISPATCH_API_KEY が未設定でも Rails は
#   問題なく起動し、呼び出し側が ConfigurationMissing を捕捉してスキップできる。
# - myblog-dispatch 側は X-Dispatch-Key ヘッダーによる共有シークレット認証を
#   要求する (myblog-dispatch:internal/authmw)。
class DispatchClient
  TIMEOUT = 10

  class ConfigurationMissing < StandardError; end
  class RequestFailed < StandardError; end

  # @param title [String] 記事タイトル
  # @param url [String] 記事の公開URL
  # @return [Hash] myblog-dispatch のレスポンス (例: { "tweet_id" => "..." })
  # @raise [ConfigurationMissing] DISPATCH_BASE_URL / DISPATCH_API_KEY が未設定
  # @raise [RequestFailed] myblog-dispatch が非2xxを返した、または通信に失敗した
  def self.post_tweet(title:, url:)
    base_url, api_key = fetch_config!

    uri = URI.join(base_url, '/tweet')
    response = post(uri, api_key, title: title, url: url)
    ensure_success!(response)

    JSON.parse(response.body)
  rescue ConfigurationMissing, RequestFailed
    raise
  rescue StandardError => e
    raise RequestFailed, "#{e.class}: #{e.message}"
  end

  def self.fetch_config!
    base_url = ENV.fetch('DISPATCH_BASE_URL', nil)
    api_key = ENV.fetch('DISPATCH_API_KEY', nil)

    if base_url.blank? || api_key.blank?
      raise ConfigurationMissing, 'DISPATCH_BASE_URL / DISPATCH_API_KEY is not configured'
    end

    [base_url, api_key]
  end
  private_class_method :fetch_config!

  def self.ensure_success!(response)
    return if response.is_a?(Net::HTTPSuccess)

    raise RequestFailed, "dispatch responded with #{response.code}: #{response.body}"
  end
  private_class_method :ensure_success!

  def self.post(uri, api_key, title:, url:)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request['X-Dispatch-Key'] = api_key
    request.body = { title: title, url: url }.to_json

    http.request(request)
  end
  private_class_method :post
end
