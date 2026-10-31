# frozen_string_literal: true

# X 連携 (OAuth) の state を、連携を開始した管理者のブラウザに紐づける Cookie。
#
# myblog-dispatch が発行する state は使い捨て・5分で失効するが、それだけでは
# 「認可URLが漏れた場合に、別のブラウザ (攻撃者) が自分の X アカウントで認可して
# ブログを攻撃者のアカウントに連携させる」ことを防げない。そこで連携開始時に state を
# Cookie に入れ、callback では Cookie の state と URL の state が一致する場合だけ
# dispatch に渡す。Cookie が無い/不一致のリクエストは dispatch を呼ばないため、
# 認証なしの callback への不正リクエストが内部通信を発生させることも防げる。
#
# Cookie は必ず暗号化する (cookies.encrypted)。攻撃者が前提とする「漏れた認可URL」には
# state が含まれるため、Cookie の値が state そのものだと、curl 等で Cookie ヘッダーを
# 自分で付けるだけで一致確認を通過できてしまう。HttpOnly / SameSite はブラウザの中の
# 制約でしかなく、これを防がない。暗号化 (+改ざん検知) により、サーバーが管理者の
# ブラウザに発行した Cookie でなければ復号できず、nil として扱われる。
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
    cookies.encrypted[COOKIE_NAME] = {
      value: state,
      expires: COOKIE_TTL.from_now,
      path: COOKIE_PATH,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :lax
    }
  end

  # 連携を開始したブラウザの Cookie に入っている state (復号できなければ nil)。
  # 読み取るだけで削除しない。照合が成立した場合だけ consume_x_connect_state で消す
  # (他人が不正な callback を送りつけても、管理者の進行中の連携を壊せないようにする)。
  def bound_x_connect_state
    cookies.encrypted[COOKIE_NAME]
  end

  # 使い捨て: 照合が成立した callback で Cookie を消す。
  def consume_x_connect_state
    cookies.delete(COOKIE_NAME, path: COOKIE_PATH)
  end

  def bound_state_matches?(bound, state)
    bound.is_a?(String) && bound.present? &&
      ActiveSupport::SecurityUtils.secure_compare(bound, state)
  end
end
