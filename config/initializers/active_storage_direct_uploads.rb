# frozen_string_literal: true

# このアプリは Active Storage のダイレクトアップロードを使わない。
# 画像の受け付けは Api::Admin::ImagesController (管理者のみ、種類とサイズを検査) に限る。
#
# Rails は POST /rails/active_storage/direct_uploads を既定で用意するが、
# この入口はアプリ側の認証を通らないため、使わない入口として 404 で閉じる。
# 画像の配信に使う blobs / representations のルートはそのまま残す
# (config.active_storage.draw_routes = false にすると配信用のルートまで消える)。
Rails.application.config.to_prepare do
  ActiveStorage::DirectUploadsController.before_action { head :not_found }
end
