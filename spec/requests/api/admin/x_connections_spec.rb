# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Admin::XConnections#create', type: :request do
  let(:admin) do
    Admin.create!(email: 'admin@example.com', password: 'password123', password_confirmation: 'password123')
  end

  let(:token) do
    post '/api/auth/sign_in',
         params: { admin: { email: admin.email, password: 'password123' } },
         as: :json
    response.headers['Authorization']
  end

  let(:authorize_url) { 'https://twitter.com/i/oauth2/authorize?response_type=code&state=state-abc' }

  describe 'POST /api/admin/x/connect' do
    context '認証されている場合' do
      it 'dispatch が発行した認可URLを返すこと' do
        allow(DispatchClient).to receive(:start_x_connect).and_return({ 'authorize_url' => authorize_url })

        post '/api/admin/x/connect', headers: { 'Authorization' => token }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['authorize_url']).to eq(authorize_url)
      end

      it '連携を開始したブラウザに state を HttpOnly / SameSite=Lax の Cookie で紐づけること' do
        allow(DispatchClient).to receive(:start_x_connect).and_return({ 'authorize_url' => authorize_url })

        post '/api/admin/x/connect', headers: { 'Authorization' => token }

        set_cookie = response.headers['Set-Cookie']
        expect(set_cookie).to include('x_connect_state=state-abc')
        expect(set_cookie).to include('httponly')
        expect(set_cookie.downcase).to include('samesite=lax')
        expect(set_cookie).to include('path=/api/admin/x')
      end

      it '不正な認可URLの場合は Cookie を発行しないこと' do
        allow(DispatchClient).to receive(:start_x_connect)
          .and_return({ 'authorize_url' => 'https://evil.example.com/x?state=abc' })

        post '/api/admin/x/connect', headers: { 'Authorization' => token }

        expect(response.headers['Set-Cookie'].to_s).not_to include('x_connect_state')
      end

      it 'x.com の認可URLも許可すること' do
        url = 'https://x.com/i/oauth2/authorize?state=state-abc'
        allow(DispatchClient).to receive(:start_x_connect).and_return({ 'authorize_url' => url })

        post '/api/admin/x/connect', headers: { 'Authorization' => token }

        expect(response).to have_http_status(:ok)
      end

      [
        'https://evil.example.com/i/oauth2/authorize?state=abc',
        'https://twitter.com@evil.example.com/i/oauth2/authorize?state=abc',
        'https://twitter.com%40evil.example.com/i/oauth2/authorize?state=abc',
        'https://twitter.com/i/oauth2/authorize',
        'https://twitter.com/i/oauth2/authorize?state=',
        'http://twitter.com/i/oauth2/authorize?state=abc',
        'https://twitter.com.evil.example.com/authorize?state=abc',
        'javascript:alert(1)',
        '',
        nil
      ].each do |bad_url|
        it "想定外の認可URL (#{bad_url.inspect}) は返さず 502 にすること" do
          allow(DispatchClient).to receive(:start_x_connect).and_return({ 'authorize_url' => bad_url })

          post '/api/admin/x/connect', headers: { 'Authorization' => token }

          expect(response).to have_http_status(:bad_gateway)
          expect(response.body).not_to include('evil.example.com')
        end
      end

      it 'X連携が未設定の場合、503を返すこと' do
        allow(DispatchClient).to receive(:start_x_connect)
          .and_raise(DispatchClient::ConfigurationMissing, 'not configured')

        post '/api/admin/x/connect', headers: { 'Authorization' => token }

        expect(response).to have_http_status(:service_unavailable)
      end

      it 'dispatch への要求が失敗した場合、502を返すこと' do
        allow(DispatchClient).to receive(:start_x_connect).and_raise(DispatchClient::RequestFailed, 'boom')

        post '/api/admin/x/connect', headers: { 'Authorization' => token }

        expect(response).to have_http_status(:bad_gateway)
      end
    end

    context '認証されていない場合' do
      it '401を返し、dispatch を呼ばないこと' do
        expect(DispatchClient).not_to receive(:start_x_connect)

        post '/api/admin/x/connect'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
