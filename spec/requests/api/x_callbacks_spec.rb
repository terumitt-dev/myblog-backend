# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::XCallbacks#show', type: :request do
  let(:admin) do
    Admin.create!(email: 'admin@example.com', password: 'password123', password_confirmation: 'password123')
  end

  let(:token) do
    post '/api/auth/sign_in',
         params: { admin: { email: admin.email, password: 'password123' } },
         as: :json
    response.headers['Authorization']
  end

  around do |example|
    original = ENV.fetch('APP_HOST', nil)
    ENV['APP_HOST'] = 'go-lilaregard.com'
    example.run
  ensure
    ENV['APP_HOST'] = original
  end

  # 管理者が「Xと連携する」を押した状態を再現する。実際のフローと同じく、
  # connect のレスポンスで発行された (暗号化された) Cookie がブラウザに保存される。
  def start_connect_as_admin(state)
    allow(DispatchClient).to receive(:start_x_connect)
      .and_return({ 'authorize_url' => "https://twitter.com/i/oauth2/authorize?state=#{state}" })
    post '/api/admin/x/connect', headers: { 'Authorization' => token }
  end

  def admin_url(result)
    "https://go-lilaregard.com/admin?x_connect=#{result}"
  end

  describe 'GET /api/admin/x/callback' do
    context '連携を開始した管理者のブラウザからの callback' do
      before { start_connect_as_admin('state-123') }

      it '管理者の JWT なしでも受け付け (X からのブラウザ遷移のため)、code/state を dispatch に渡して成功を通知すること' do
        expect(DispatchClient).to receive(:complete_x_connect).with(code: 'auth-code', state: 'state-123')
                                                              .and_return({ 'status' => 'connected' })

        get '/api/admin/x/callback', params: { code: 'auth-code', state: 'state-123' }

        expect(response).to have_http_status(:found)
        expect(response.location).to eq(admin_url('success'))
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

      it 'X の認可画面で拒否された場合、dispatch を呼ばずに denied を通知し、Cookie を消すこと' do
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback', params: { error: 'access_denied', state: 'state-123' }

        expect(response.location).to eq(admin_url('denied'))
        expect(response.headers['Set-Cookie']).to include('x_connect_state=;', 'max-age=0')
      end

      [
        {},
        { code: '' },
        { code: 'a' * 1025 },
        { code: ['array'] },
        { code: { 'k' => 'v' } }
      ].each do |bad_code|
        it "不正な code (#{bad_code.to_s[0, 40]}) は dispatch を呼ばずに error を通知すること" do
          expect(DispatchClient).not_to receive(:complete_x_connect)

          get '/api/admin/x/callback', params: { state: 'state-123' }.merge(bad_code)

          expect(response.location).to eq(admin_url('error'))
        end
      end

      it 'state が不正・期限切れ等で dispatch が失敗した場合、error を通知すること' do
        allow(DispatchClient).to receive(:complete_x_connect)
          .and_raise(DispatchClient::RequestFailed, 'dispatch responded with 422')

        get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }

        expect(response).to have_http_status(:found)
        expect(response.location).to eq(admin_url('error'))
      end

      it 'X連携が未設定の場合も error を通知すること' do
        allow(DispatchClient).to receive(:complete_x_connect)
          .and_raise(DispatchClient::ConfigurationMissing, 'not configured')

        get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }

        expect(response.location).to eq(admin_url('error'))
      end

      it 'dispatch のエラー内容や code / state を自前のログに出さないこと' do
        allow(DispatchClient).to receive(:complete_x_connect)
          .and_raise(DispatchClient::RequestFailed, 'dispatch responded with 422')
        allow(Rails.logger).to receive(:error)

        get '/api/admin/x/callback', params: { code: 'secret-code-xyz', state: 'state-123' }

        expect(Rails.logger).to have_received(:error).with(satisfy { |msg|
          msg.exclude?('secret-code-xyz') && msg.exclude?('state-123')
        })
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

      it 'Cookie は使い捨てで、成功後は同じ state で再度完了できないこと' do
        allow(DispatchClient).to receive(:complete_x_connect).and_return({ 'status' => 'connected' })

        get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }
        expect(response.location).to eq(admin_url('success'))
        expect(response.headers['Set-Cookie']).to include('x_connect_state=;', 'max-age=0')

        # ブラウザはサーバーの削除指示に従い、Cookie を送らなくなる。
        expect(DispatchClient).not_to receive(:complete_x_connect)
        get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }, headers: { 'Cookie' => '' }
        expect(response.location).to eq(admin_url('error'))
      end
    end

    context '連携を開始した管理者のブラウザ以外からの callback (認可URLが漏れた場合など)' do
      it 'Cookie が無い場合、dispatch を呼ばずに error にすること' do
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback', params: { code: 'attacker-code', state: 'leaked-state' }

        expect(response.location).to eq(admin_url('error'))
      end

      # 攻撃者は漏れた認可URLから state を知っている。curl 等で Cookie ヘッダーを自分で付けても、
      # 管理者のブラウザに発行された暗号化 Cookie でなければ通らない。
      it 'state の値をそのまま入れた偽の Cookie (平文) を付けても、dispatch を呼ばずに error にすること' do
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback',
            params: { code: 'attacker-code', state: 'leaked-state' },
            headers: { 'Cookie' => 'x_connect_state=leaked-state' }

        expect(response.location).to eq(admin_url('error'))
      end

      it '改ざんした Cookie を付けても、dispatch を呼ばずに error にすること' do
        start_connect_as_admin('state-123')
        issued = response.headers['Set-Cookie'][/x_connect_state=([^;]+)/, 1]
        tampered = "#{issued[0..-3]}xx"
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback',
            params: { code: 'c', state: 'state-123' },
            headers: { 'Cookie' => "x_connect_state=#{tampered}" }

        expect(response.location).to eq(admin_url('error'))
      end

      it 'Cookie の state と URL の state が一致しない場合、dispatch を呼ばずに error にすること' do
        start_connect_as_admin('state-123')
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback', params: { code: 'c', state: 'another-state' }

        expect(response.location).to eq(admin_url('error'))
      end

      it '不一致・偽造の callback は管理者の Cookie に触れず、進行中の連携を壊さないこと' do
        start_connect_as_admin('state-123')
        allow(DispatchClient).to receive(:complete_x_connect).and_return({ 'status' => 'connected' })

        # 罠のリンク (?error=...) や別の state の callback が、管理者の Cookie を消さない。
        get '/api/admin/x/callback', params: { error: 'x', state: 'another-state' }
        expect(response.location).to eq(admin_url('error'))
        expect(response.headers['Set-Cookie'].to_s).not_to include('x_connect_state')

        get '/api/admin/x/callback', params: { code: 'c', state: 'state-123' }
        expect(response.location).to eq(admin_url('success'))
      end

      it 'state が無い、または不正な型の場合も dispatch を呼ばずに error にすること' do
        start_connect_as_admin('state-123')
        expect(DispatchClient).not_to receive(:complete_x_connect)

        get '/api/admin/x/callback', params: { code: 'c' }
        expect(response.location).to eq(admin_url('error'))

        get '/api/admin/x/callback', params: { code: 'c', state: ['state-123'] }
        expect(response.location).to eq(admin_url('error'))
      end
    end
  end
end
