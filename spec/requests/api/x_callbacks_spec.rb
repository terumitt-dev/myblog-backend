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

  # 連携を開始したブラウザ (Cookie に state が紐づいている) を再現する。
  def bind_state(state)
    cookies[:x_connect_state] = state
  end

  describe 'GET /api/admin/x/callback' do
    # 既定では、連携を開始したブラウザ (Cookie あり) からの callback。
    # Cookie なしを試す例は metadata で外す。
    before { bind_state('state-123') unless RSpec.current_example.metadata[:without_cookie] }

    it '管理者の JWT なしでも受け付け (X からのブラウザ遷移のため)、code/state を dispatch に渡して成功を通知すること' do
      expect(DispatchClient).to receive(:complete_x_connect).with(code: 'auth-code', state: 'state-123')
                                                            .and_return({ 'status' => 'connected' })

      get '/api/admin/x/callback', params: { code: 'auth-code', state: 'state-123' }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=success')
    end

    it 'リダイレクト先に code / state を含めないこと' do
      allow(DispatchClient).to receive(:complete_x_connect).and_return({ 'status' => 'connected' })

      get '/api/admin/x/callback', params: { code: 'secret-code-xyz', state: 'state-123' }

      expect(response.location).not_to include('secret-code-xyz')
      expect(response.location).not_to include('state-123')
    end

    it 'レスポンスをキャッシュさせないこと' do
      allow(DispatchClient).to receive(:complete_x_connect).and_return({ 'status' => 'connected' })

      get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }

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

      get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }

      expect(response).to have_http_status(:found)
      expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=error')
    end

    it 'X連携が未設定の場合も error を通知すること' do
      allow(DispatchClient).to receive(:complete_x_connect)
        .and_raise(DispatchClient::ConfigurationMissing, 'not configured')

      get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }

      expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=error')
    end

    context '連携を開始したブラウザ以外からの callback (認可URLが漏れた場合など)' do
      it 'Cookie が無い場合、dispatch を呼ばずに error にすること', :without_cookie do
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback', params: { code: 'attacker-code', state: 'state-123' }

        expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=error')
      end

      it 'Cookie の state と URL の state が一致しない場合、dispatch を呼ばずに error にすること' do
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback', params: { code: 'c', state: 'another-state' }

        expect(response.location).to eq('https://go-lilaregard.com/admin?x_connect=error')
      end

      it 'Cookie は使い捨てで、成功後は同じ state で再度完了できないこと' do
        allow(DispatchClient).to receive(:complete_x_connect).and_return({ 'status' => 'connected' })

        get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }
        expect(response.location).to end_with('x_connect=success')
        # サーバーが返した削除指示 (max-age=0) に従い、ブラウザは Cookie を送らなくなる。
        expect(response.headers['Set-Cookie']).to include('x_connect_state=;', 'max-age=0')

        expect(DispatchClient).not_to receive(:complete_x_connect)
        get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' },
                                     headers: { 'Cookie' => '' }
        expect(response.location).to end_with('x_connect=error')
      end

      it '拒否 (error=access_denied) の場合も Cookie を消すこと' do
        get '/api/admin/x/callback', params: { error: 'access_denied', state: 'state-123' }

        expect(response.headers['Set-Cookie'].to_s).to include('x_connect_state=;')
      end
    end

    it 'Rails 標準のリクエストログ (Started GET / Parameters) にも code / state を出さないこと' do
      io = StringIO.new
      original = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(io)
      allow(DispatchClient).to receive(:complete_x_connect).and_return({ 'status' => 'connected' })

      get '/api/admin/x/callback', params: { code: 'LEAKCHECK-CODE', state: 'state-123' }

      Rails.logger = original
      expect(io.string).to include('/api/admin/x/callback')
      expect(io.string).not_to include('LEAKCHECK-CODE')
      expect(io.string).not_to include('state-123')
    end

    it 'dispatch のエラー内容や code / state をログに出さないこと' do
      allow(DispatchClient).to receive(:complete_x_connect)
        .and_raise(DispatchClient::RequestFailed, 'dispatch responded with 422')
      allow(Rails.logger).to receive(:error)

      get '/api/admin/x/callback', params: { code: 'secret-code-xyz', state: 'state-123' }

      expect(Rails.logger).to have_received(:error).with(satisfy { |msg|
        msg.exclude?('secret-code-xyz') && msg.exclude?('state-123')
      })
    end
  end
end
