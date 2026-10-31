# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# myblog-dispatch (X/Twitter 連携用マイクロサービス) の内部 API を呼び出す。
#   - POST /tweet            : 記事のツイート
#   - POST /oauth/connect    : X 連携 (OAuth Authorization Code + PKCE) の認可 URL 発行
#   - POST /oauth/callback   : X から戻った code / state の転送 (トークン交換・保存)
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
  #
  # DISPATCH_BASE_URL はスキーム+ホスト(+ポート)のみを想定 (例: "https://dispatch.internal")。
  # URI.join でパスを "/tweet" に絶対指定するため、末尾にパスを含めても無視される。
  def self.post_tweet(title:, url:)
    post_json('/tweet', title: title, url: url)
  end

  # X 連携を開始し、X の認可画面へ遷移するための URL を発行する。
  # @return [Hash] 例: { "authorize_url" => "https://twitter.com/i/oauth2/authorize?..." }
  # @raise [ConfigurationMissing] DISPATCH_BASE_URL / DISPATCH_API_KEY が未設定
  # @raise [RequestFailed] myblog-dispatch が非2xxを返した、または通信に失敗した
  def self.start_x_connect
    post_json('/oauth/connect', {})
  end

  # X の認可後に戻ってきた code / state を myblog-dispatch に渡し、トークン交換・保存させる。
  # @return [Hash] 例: { "status" => "connected" }
  # @raise [ConfigurationMissing] DISPATCH_BASE_URL / DISPATCH_API_KEY が未設定
  # @raise [RequestFailed] state 不正・期限切れ、X 側のエラー、通信失敗など
  def self.complete_x_connect(code:, state:)
    post_json('/oauth/callback', code: code, state: state)
  end

  def self.post_json(path, payload)
    base_url, api_key = fetch_config!

    uri = URI.join(base_url, path)
    response = post(uri, api_key, payload)
    ensure_success!(response)

    JSON.parse(response.body)
  rescue ConfigurationMissing, RequestFailed
    raise
  rescue StandardError => e
    raise RequestFailed, "#{e.class}: #{e.message}"
  end
  private_class_method :post_json

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

  def self.post(uri, api_key, payload)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request['X-Dispatch-Key'] = api_key
    request.body = payload.to_json

    http.request(request)
  end
  private_class_method :post
end
