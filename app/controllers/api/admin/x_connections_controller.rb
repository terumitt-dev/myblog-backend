# frozen_string_literal: true

module Api
  module Admin
    # X (Twitter) 連携の開始 (管理者のみ)。
    # myblog-dispatch に state / PKCE を発行させ、X の認可画面へ遷移するための URL を返す。
    # X からの戻り (callback) は Api::XCallbacksController が受ける。
    class XConnectionsController < ApplicationController
      # myblog-dispatch が返した URL をそのままブラウザに遷移させるため、
      # 想定外のホストを指していないことを確認する (dispatch が改ざんされた場合に
      # 管理者をフィッシングサイトへ誘導させない防御)。
      ALLOWED_AUTHORIZE_HOSTS = %w[twitter.com x.com].freeze

      before_action :authenticate_admin!

      # POST /api/admin/x/connect
      def create
        result = DispatchClient.start_x_connect
        authorize_url = result['authorize_url']

        unless trusted_authorize_url?(authorize_url)
          Rails.logger.error('Api::Admin::XConnectionsController#create: unexpected authorize_url from dispatch')
          return render json: { error: 'Failed to start X connection' }, status: :bad_gateway
        end

        render json: { authorize_url: authorize_url }, status: :ok
      rescue DispatchClient::ConfigurationMissing => e
        Rails.logger.info("Api::Admin::XConnectionsController#create: dispatch not configured: #{e.message}")
        render json: { error: 'X connection is not configured' }, status: :service_unavailable
      rescue DispatchClient::RequestFailed => e
        Rails.logger.error("Api::Admin::XConnectionsController#create: #{e.message}")
        render json: { error: 'Failed to start X connection' }, status: :bad_gateway
      end

      private

      def trusted_authorize_url?(value)
        return false unless value.is_a?(String)

        uri = URI.parse(value)
        uri.is_a?(URI::HTTPS) && ALLOWED_AUTHORIZE_HOSTS.include?(uri.host)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
