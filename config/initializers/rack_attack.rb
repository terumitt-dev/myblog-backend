# frozen_string_literal: true

# Rack::Attack レートリミット設定
# パスワードリセット等のセンシティブエンドポイントへの総当たり攻撃を防止
#
# カウンタは Rails.cache (本番では SolidCache) に保存することで、
# 複数 Puma worker / 複数 Pod 構成でもプロセスをまたいで共有される。
# プロセスローカルなストアのままだと password_reset/global などの
# 全体スロットリングがプロセスごとに分断され、実質的に Pod 数 × worker 数倍の
# 回数を通せてしまう。
#
# 本番では「共有可能と分かっているストアだけを allow-list で許可」する方針。
# MemoryStore だけ deny-list で弾く方式だと、null_store / file_store など
# 他のプロセスローカルストアが設定された場合にすり抜ける余地が残るため。
SHARED_CACHE_STORES = %i[solid_cache_store redis_cache_store mem_cache_store].freeze

if Rails.env.production?
  configured_store = Array(Rails.application.config.cache_store).first&.to_sym
  unless SHARED_CACHE_STORES.include?(configured_store)
    raise 'Rack::Attack requires a shared cache store in production ' \
          "(got #{configured_store.inspect}; " \
          "use one of #{SHARED_CACHE_STORES.inspect})"
  end
end

Rack::Attack.cache.store = Rails.cache

class Rack::Attack
  # 実クライアントIPを取得
  # ActionDispatch::Request#remote_ip は Rails の trusted_proxies 設定を
  # 考慮して安全にクライアントIPを返すため、XFFの偽装攻撃にも対応できる。
  # 不正な X-Forwarded-For ヘッダで例外化するケースがあるため、
  # その場合は REMOTE_ADDR (実コネクションIP) にフォールバックする。
  # req.ip だと XFF 由来の偽装値を再利用する余地があるため避ける。
  # 例外を上に伝えると 500 になり DoS の踏み台になるためフォールバックは必須。
  def self.client_ip(req)
    ActionDispatch::Request.new(req.env).remote_ip.to_s
  rescue StandardError
    req.get_header('REMOTE_ADDR').to_s
  end

  # /api/auth/password と /api/auth/password.json などのフォーマット付き URL を
  # 同一エンドポイントとして判定する。req.path の完全一致だと、Rails のルーティングが
  # 暗黙に許す .json 等のフォーマット拡張で rate limit を回避されうるため。
  PASSWORD_ENDPOINT = %r{\A/api/auth/password(?:\.[^/]+)?/?\z}.freeze

  def self.password_endpoint?(req)
    req.path.match?(PASSWORD_ENDPOINT)
  end

  # パスワードリセット要求（SECRET 検証）: 同一IPから1時間に5回まで
  # - SECRET のブルートフォースを抑制
  # - メール爆撃の二重防御
  throttle('password_reset/ip', limit: 5, period: 1.hour) do |req|
    client_ip(req) if password_endpoint?(req) && req.post?
  end

  # パスワードリセット要求（全体）: 1時間に20回まで
  # - 分散IP攻撃による admin へのメール爆撃を防止
  # - 正規ユーザー（admin 1人）に対する影響はゼロに等しい
  throttle('password_reset/global', limit: 20, period: 1.hour) do |req|
    'password_reset' if password_endpoint?(req) && req.post?
  end

  # パスワードリセット実行（トークン検証）: 同一IPから1時間に10回まで
  # Devise のトークンは十分長いが多層防御として追加
  throttle('password_reset_update/ip', limit: 10, period: 1.hour) do |req|
    client_ip(req) if password_endpoint?(req) && req.patch?
  end

  # ログイン・管理者登録・コメント投稿も、password と同じ理由でフォーマット拡張
  # (.json 等) と末尾スラッシュを同一エンドポイントとして判定する。
  SIGN_IN_ENDPOINT = %r{\A/api/auth/sign_in(?:\.[^/]+)?/?\z}
  SIGN_UP_ENDPOINT = %r{\A/api/auth/sign_up(?:\.[^/]+)?/?\z}
  COMMENTS_ENDPOINT = %r{\A/api/blogs/[^/]+/comments(?:\.[^/]+)?/?\z}

  # ログイン: 同一IPから10分に10回まで
  # - 管理者パスワードの総当たりを抑制
  # - 全体 (global) の上限は置かない。置くと第三者が上限まで叩くだけで
  #   管理者本人がログインできなくなる (ロックアウト攻撃) ため
  throttle('sign_in/ip', limit: 10, period: 10.minutes) do |req|
    client_ip(req) if req.post? && req.path.match?(SIGN_IN_ENDPOINT)
  end

  # 管理者登録 (合言葉 ADMIN_SIGNUP_PASSWORD の検証): 同一IPから1時間に5回まで
  # - 応答で合言葉の正誤が分かるため、総当たりを抑制する
  throttle('sign_up/ip', limit: 5, period: 1.hour) do |req|
    client_ip(req) if req.post? && req.path.match?(SIGN_UP_ENDPOINT)
  end

  # 管理者登録 (全体): 1時間に20回まで
  # - 分散IPからの合言葉の総当たりを抑制
  # - 管理者は1人で、登録は初期構築時にしか使わないため正規利用への影響はない
  throttle('sign_up/global', limit: 20, period: 1.hour) do |req|
    'sign_up' if req.post? && req.path.match?(SIGN_UP_ENDPOINT)
  end

  # コメント投稿: 同一IPから10分に20回まで
  # - Turnstile を通過した場合でも連投できる量を抑える
  # - 無効な token での連打による Cloudflare siteverify への外部リクエスト量も抑える
  throttle('comments/ip', limit: 20, period: 10.minutes) do |req|
    client_ip(req) if req.post? && req.path.match?(COMMENTS_ENDPOINT)
  end

  # レートリミット超過時のレスポンス
  # throttled_responder には env ではなく Rack::Attack::Request が渡される
  # (env を受け取るのは廃止された throttled_response の方)。
  self.throttled_responder = lambda do |request|
    retry_after = (request.env['rack.attack.match_data'] || {})[:period]
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After' => retry_after.to_s
      },
      [{ error: 'Too many requests. Please try again later.' }.to_json]
    ]
  end
end
