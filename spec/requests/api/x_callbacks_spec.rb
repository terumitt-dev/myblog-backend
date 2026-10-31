# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::XCallbacks#show', type: :request do
  around do |example|
    original = ENV.fetch('APP_HOST', nil)
    ENV['APP_HOST'] = 'go-lilaregard.com'
    example.run
  ensure
    ENV['APP_HOST'] = original
  end

  describe 'GET /api/admin/x/callback' do
    it '管理者の JWT なしでも受け付け (X からのブラウザ遷移のため)、code/state を dispatch に渡して成功を通知すること' do
      expect(DispatchClient).to receive(:complete_x_connect).with(code: 'auth-code', state: 'state-123')
                                                            .and_return({ 'status' => 'connected' })

      get '/api/admin/x/callback', params: { code: 'auth-code', state: 'state-123' }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=success')
    end

    it 'リダイレクト先に code / state を含めないこと' do
      allow(DispatchClient).to receive(:complete_x_connect).and_return({ 'status' => 'connected' })

      get '/api/admin/x/callback', params: { code: 'secret-code-xyz', state: 'secret-state-xyz' }

      expect(response.location).not_to include('secret-code-xyz')
      expect(response.location).not_to include('secret-state-xyz')
    end

    it 'レスポンスをキャッシュさせないこと' do
      allow(DispatchClient).to receive(:complete_x_connect).and_return({ 'status' => 'connected' })

      get '/api/admin/x/callback', params: { code: 'c', state: 's' }

      expect(response.headers['Cache-Control']).to eq('no-store')
    end

    it 'X の認可画面で拒否された場合、dispatch を呼ばずに denied を通知すること' do
      expect(DispatchClient).not_to receive(:complete_x_connect)

      get '/api/admin/x/callback', params: { error: 'access_denied', state: 'state-123' }

      expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=denied')
    end

    [
      {},
      { code: 'only-code' },
      { state: 'only-state' },
      { code: '', state: 'state-123' },
      { code: 'a' * 1025, state: 'state-123' },
      { code: ['array'], state: 'state-123' },
      { code: { 'k' => 'v' }, state: 'state-123' }
    ].each do |bad_params|
      it "不正なパラメータ (#{bad_params.to_s[0, 40]}) は dispatch を呼ばずに error を通知すること" do
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback', params: bad_params

        expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=error')
      end
    end

    it 'state が不正・期限切れ等で dispatch が失敗した場合、error を通知すること' do
      allow(DispatchClient).to receive(:complete_x_connect)
        .and_raise(DispatchClient::RequestFailed, 'dispatch responded with 422')

      get '/api/admin/x/callback', params: { code: 'c', state: 's' }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=error')
    end

    it 'X連携が未設定の場合も error を通知すること' do
      allow(DispatchClient).to receive(:complete_x_connect)
        .and_raise(DispatchClient::ConfigurationMissing, 'not configured')

      get '/api/admin/x/callback', params: { code: 'c', state: 's' }

      expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=error')
    end

    it 'dispatch のエラー内容や code / state をログに出さないこと' do
      allow(DispatchClient).to receive(:complete_x_connect)
        .and_raise(DispatchClient::RequestFailed, 'dispatch responded with 422')
      allow(Rails.logger).to receive(:error)

      get '/api/admin/x/callback', params: { code: 'secret-code-xyz', state: 'secret-state-xyz' }

      expect(Rails.logger).to have_received(:error).with(satisfy { |msg|
        msg.exclude?('secret-code-xyz') && msg.exclude?('secret-state-xyz')
      })
    end
  end
end
