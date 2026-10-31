# frozen_string_literal: true

# X 連携 (OAuth) の state を、連携を開始した管理者のブラウザに紐づける Cookie。
#
# myblog-dispatch が発行する state は使い捨て・5分で失効するが、それだけでは
# 「認可URLが漏れた場合に、別のブラウザ (攻撃者) が自分の X アカウントで認可して
# ブログを攻撃者のアカウントに連携させる」ことを防げない。そこで連携開始時に state を
# HttpOnly Cookie に入れ、callback では Cookie の state と URL の state が一致する
# 場合だけ dispatch に渡す。Cookie が無い/不一致のリクエストは dispatch を呼ばないため、
# 認証なしの callback への不正リクエストが内部通信を発生させることも防げる。
#
# SameSite=Lax: X からのトップレベルの GET リダイレクトでは送信され、
# 他サイトからのサブリクエストでは送信されない。
module XConnectStateCookie
  extend ActiveSupport::Concern

  COOKIE_NAME = :x_connect_state
  COOKIE_PATH = '/api/admin/x'
  # myblog-dispatch の state の TTL (internal/oauthflow, 5分) に合わせる。
  COOKIE_TTL = 5.minutes

  included do
    include ActionController::Cookies
  end

  private

  def bind_x_connect_state(state)
    cookies[COOKIE_NAME] = {
      value: state,
      expires: COOKIE_TTL.from_now,
      path: COOKIE_PATH,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
  end

  # Cookie の state を取り出し、同時に削除する (成否に関わらず使い捨て)。
  def take_bound_x_connect_state
    value = cookies[COOKIE_NAME]
    cookies.delete(COOKIE_NAME, path: COOKIE_PATH)
    value
  end

  def bound_state_matches?(bound, state)
    bound.is_a?(String) && bound.present? &&
      ActiveSupport::SecurityUtils.secure_compare(bound, state)
  end
end
