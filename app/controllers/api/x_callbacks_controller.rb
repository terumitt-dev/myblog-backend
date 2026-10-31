# frozen_string_literal: true

module Api
  # X (Twitter) の OAuth 認可後のリダイレクト先 (GET /api/admin/x/callback)。
  #
  # X からの戻りはブラウザの画面遷移であり、管理画面の JWT (Authorization ヘッダー)
  # を付けられないため、管理者認証 (authenticate_admin!) の対象外にしている。
  # 認可の正当性は myblog-dispatch が検証する state (管理者の連携開始時に発行・
  # 5分で失効・使い捨て) と、それに紐づく PKCE の code_verifier で担保される。
  # admin 名前空間の認証をうっかり外す/付けることがないよう、別コントローラーにしている。
  #
  # 結果は管理画面へのリダイレクト (?x_connect=success|denied|error) で伝える。
  # code / state / エラー詳細は URL にもログにも出さない。
  class XCallbacksController < ApplicationController
    # code / state は X と myblog-dispatch が生成する不透明な文字列で、形式は検証しない
    # (JSON として安全にエンコードして転送するだけ)。異常に長い入力だけを弾く。
    MAX_PARAM_LENGTH = 1024

    # GET /api/admin/x/callback
    def show
      redirect_to_admin(connect_result)
    end

    private

    # X の認可結果を処理し、管理画面に伝える結果 (success / denied / error) を返す。
    def connect_result
      # 管理者が X の認可画面で「拒否」した場合は error=access_denied が付いて戻る。
      return 'denied' if params[:error].present?

      code = params[:code]
      state = params[:state]
      return 'error' unless valid_param?(code) && valid_param?(state)

      DispatchClient.complete_x_connect(code: code, state: state)
      'success'
    rescue DispatchClient::ConfigurationMissing => e
      Rails.logger.info("Api::XCallbacksController#show: dispatch not configured: #{e.message}")
      'error'
    rescue DispatchClient::RequestFailed => e
      Rails.logger.error("Api::XCallbacksController#show: #{e.message}")
      'error'
    end

    def valid_param?(value)
      value.is_a?(String) && value.present? && value.length <= MAX_PARAM_LENGTH
    end

    # 遷移先は ENV (APP_HOST) から組み立てた固定のパスで、ユーザー入力を含まない。
    def redirect_to_admin(result)
      host = ENV.fetch('APP_HOST', 'localhost:3000')
      redirect_to "https://#{host}/admin?x_connect=#{result}", allow_other_host: true
    end
  end
end
