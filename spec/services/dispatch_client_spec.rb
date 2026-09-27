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
