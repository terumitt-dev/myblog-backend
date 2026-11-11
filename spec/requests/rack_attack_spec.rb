# frozen_string_literal: true

require 'rails_helper'

# Rack::Attack のレートリミット (config/initializers/rack_attack.rb) のリクエストスペック。
# test 環境の cache_store は :null_store でカウンタが保存されないため、
# このスペックの間だけ MemoryStore に差し替えて実際に 429 になることを確認する。
RSpec.describe 'Rack::Attack throttles', type: :request do
  around(:each) do |example|
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = original_store
  end

  let(:json_headers) { { 'Content-Type' => 'application/json' } }

  def from_ip(ip)
    json_headers.merge('REMOTE_ADDR' => ip)
  end

  describe 'POST /api/auth/password (同一IPから1時間に5回まで)' do
    # 以前は throttled_responder が例外になり、上限超過時に 429 ではなく 500 を返していた。
    it '6回目で 500 ではなく 429 と Retry-After を返すこと' do
      body = { secret: 'wrong-secret' }.to_json
      5.times do
        post '/api/auth/password', params: body, headers: from_ip('203.0.113.5')
        expect(response).to have_http_status(:accepted)
      end

      post '/api/auth/password', params: body, headers: from_ip('203.0.113.5')
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After']).to eq('3600')
      expect(response.parsed_body['error']).to be_present
    end
  end

  describe 'POST /api/auth/sign_in (同一IPから10分に10回まで)' do
    let(:body) { { admin: { email: 'nobody@example.com', password: 'wrong-password-123' } }.to_json }

    it '11回目で 429 を返すこと' do
      10.times do
        post '/api/auth/sign_in', params: body, headers: from_ip('203.0.113.10')
        expect(response).to have_http_status(:unauthorized)
      end

      post '/api/auth/sign_in', params: body, headers: from_ip('203.0.113.10')
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers['Retry-After']).to eq('600')
    end

    it '別のIPは制限されないこと (管理者本人をロックアウトしない)' do
      11.times { post '/api/auth/sign_in', params: body, headers: from_ip('203.0.113.10') }
      expect(response).to have_http_status(:too_many_requests)

      post '/api/auth/sign_in', params: body, headers: from_ip('203.0.113.11')
      expect(response).to have_http_status(:unauthorized)
    end

    it 'フォーマット拡張 (.json) や末尾スラッシュでも同じカウンタで制限されること' do
      5.times { post '/api/auth/sign_in', params: body, headers: from_ip('203.0.113.10') }
      5.times { post '/api/auth/sign_in.json', params: body, headers: from_ip('203.0.113.10') }

      post '/api/auth/sign_in/', params: body, headers: from_ip('203.0.113.10')
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'POST /api/auth/sign_up' do
    let(:body) do
      {
        admin: { email: 'new@example.com', password: 'password12345', password_confirmation: 'password12345' },
        signup_password: 'wrong-signup-password'
      }.to_json
    end

    it '同一IPからは1時間に5回まで (6回目で 429)' do
      5.times do
        post '/api/auth/sign_up', params: body, headers: from_ip('203.0.113.20')
        expect(response).to have_http_status(:forbidden)
      end

      post '/api/auth/sign_up', params: body, headers: from_ip('203.0.113.20')
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'IPを変えても全体で1時間に20回まで (21回目で 429)' do
      20.times do |i|
        post '/api/auth/sign_up', params: body, headers: from_ip("198.51.100.#{i + 1}")
        expect(response).to have_http_status(:forbidden)
      end

      post '/api/auth/sign_up', params: body, headers: from_ip('198.51.100.200')
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'POST /api/blogs/:blog_id/comments (同一IPから10分に20回まで)' do
    let(:blog) { create(:blog) }
    let(:body) { { comment: { user_name: 'taro', comment: 'hi' }, turnstile_token: 'bad-token' }.to_json }

    before { allow(TurnstileService).to receive(:verify).and_return(false) }

    it '21回目で 429 を返し、Turnstile の検証 (外部リクエスト) も行わないこと' do
      20.times do
        post "/api/blogs/#{blog.id}/comments", params: body, headers: from_ip('203.0.113.30')
        expect(response).to have_http_status(:unprocessable_entity)
      end
      expect(TurnstileService).to have_received(:verify).exactly(20).times

      post "/api/blogs/#{blog.id}/comments", params: body, headers: from_ip('203.0.113.30')
      expect(response).to have_http_status(:too_many_requests)
      expect(TurnstileService).to have_received(:verify).exactly(20).times
    end

    it 'コメントの閲覧 (GET) は制限しないこと' do
      25.times { get "/api/blogs/#{blog.id}/comments", headers: from_ip('203.0.113.30') }
      expect(response).to have_http_status(:ok)
    end
  end
end
