# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DispatchClient do
  # Net::HTTP のレスポンスを差し替えるヘルパー (turnstile_service_spec.rb と同じ方針)
  def stub_http(http_double)
    allow(Net::HTTP).to receive(:new).and_return(http_double)
    allow(http_double).to receive(:use_ssl=)
    allow(http_double).to receive(:open_timeout=)
    allow(http_double).to receive(:read_timeout=)
  end

  def make_response(code, body:)
    response = Net::HTTPResponse::CODE_TO_OBJ[code].new('1.1', code, 'OK')
    allow(response).to receive(:body).and_return(body)
    response
  end

  around do |example|
    original_base_url = ENV.fetch('DISPATCH_BASE_URL', nil)
    original_api_key = ENV.fetch('DISPATCH_API_KEY', nil)
    example.run
  ensure
    ENV['DISPATCH_BASE_URL'] = original_base_url
    ENV['DISPATCH_API_KEY'] = original_api_key
  end

  describe '.start_x_connect / .complete_x_connect' do
    before do
      ENV['DISPATCH_BASE_URL'] = 'https://dispatch.internal'
      ENV['DISPATCH_API_KEY'] = 'test-dispatch-key'
    end

    it 'start_x_connect は /oauth/connect を共有シークレット付きで呼び、認可URLを返すこと' do
      http = instance_double(Net::HTTP)
      stub_http(http)
      allow(http).to receive(:request) do |request|
        expect(request.path).to eq('/oauth/connect')
        expect(request['X-Dispatch-Key']).to eq('test-dispatch-key')
        make_response('200', body: { authorize_url: 'https://twitter.com/i/oauth2/authorize?x=1' }.to_json)
      end

      result = described_class.start_x_connect

      expect(result['authorize_url']).to eq('https://twitter.com/i/oauth2/authorize?x=1')
    end

    it 'complete_x_connect は /oauth/callback に code と state を JSON で渡すこと' do
      http = instance_double(Net::HTTP)
      stub_http(http)
      allow(http).to receive(:request) do |request|
        expect(request.path).to eq('/oauth/callback')
        expect(request['X-Dispatch-Key']).to eq('test-dispatch-key')
        expect(JSON.parse(request.body)).to eq('code' => 'auth-code', 'state' => 'state-123')
        make_response('200', body: { status: 'connected' }.to_json)
      end

      result = described_class.complete_x_connect(code: 'auth-code', state: 'state-123')

      expect(result['status']).to eq('connected')
    end

    it 'complete_x_connect は dispatch が 422 (state不正等) を返した場合 RequestFailed を発生させること' do
      http = instance_double(Net::HTTP)
      stub_http(http)
      allow(http).to receive(:request).and_return(make_response('422', body: '{"error":"invalid or expired state"}'))

      expect do
        described_class.complete_x_connect(code: 'c', state: 's')
      end.to raise_error(DispatchClient::RequestFailed, /422/)
    end

    it '設定が未設定の場合 ConfigurationMissing を発生させること' do
      ENV['DISPATCH_API_KEY'] = nil

      expect { described_class.start_x_connect }.to raise_error(DispatchClient::ConfigurationMissing)
      expect do
        described_class.complete_x_connect(code: 'c', state: 's')
      end.to raise_error(DispatchClient::ConfigurationMissing)
    end
  end

  describe '.post_tweet' do
    context 'DISPATCH_BASE_URL / DISPATCH_API_KEY が設定されている場合' do
      before do
        ENV['DISPATCH_BASE_URL'] = 'https://dispatch.internal'
        ENV['DISPATCH_API_KEY'] = 'test-dispatch-key'
      end

      it '成功時に tweet_id を含むレスポンスをパースして返すこと' do
        http = instance_double(Net::HTTP)
        stub_http(http)
        allow(http).to receive(:request) do |request|
          expect(request['X-Dispatch-Key']).to eq('test-dispatch-key')
          expect(JSON.parse(request.body)).to eq('title' => 'タイトル', 'url' => 'https://go-lilaregard.com/posts/1')
          make_response('201', body: { tweet_id: '12345' }.to_json)
        end

        result = described_class.post_tweet(title: 'タイトル', url: 'https://go-lilaregard.com/posts/1')

        expect(result['tweet_id']).to eq('12345')
      end

      it 'myblog-dispatch が非2xxを返した場合 RequestFailed を発生させること' do
        http = instance_double(Net::HTTP)
        stub_http(http)
        allow(http).to receive(:request).and_return(make_response('401', body: '{"error":"unauthorized"}'))

        expect do
          described_class.post_tweet(title: 'タイトル', url: 'https://go-lilaregard.com/posts/1')
        end.to raise_error(DispatchClient::RequestFailed)
      end

      it '通信エラー時に RequestFailed でラップすること' do
        http = instance_double(Net::HTTP)
        stub_http(http)
        allow(http).to receive(:request).and_raise(Net::OpenTimeout)

        expect do
          described_class.post_tweet(title: 'タイトル', url: 'https://go-lilaregard.com/posts/1')
        end.to raise_error(DispatchClient::RequestFailed)
      end
    end

    context 'DISPATCH_BASE_URL が未設定の場合' do
      before do
        ENV['DISPATCH_BASE_URL'] = nil
        ENV['DISPATCH_API_KEY'] = 'test-dispatch-key'
      end

      it 'ConfigurationMissing を発生させること' do
        expect do
          described_class.post_tweet(title: 'タイトル', url: 'https://go-lilaregard.com/posts/1')
        end.to raise_error(DispatchClient::ConfigurationMissing)
      end
    end

    context 'DISPATCH_API_KEY が未設定の場合' do
      before do
        ENV['DISPATCH_BASE_URL'] = 'https://dispatch.internal'
        ENV['DISPATCH_API_KEY'] = nil
      end

      it 'ConfigurationMissing を発生させること' do
        expect do
          described_class.post_tweet(title: 'タイトル', url: 'https://go-lilaregard.com/posts/1')
        end.to raise_error(DispatchClient::ConfigurationMissing)
      end
    end
  end
end
