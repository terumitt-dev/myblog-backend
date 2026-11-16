# frozen_string_literal: true

require 'rails_helper'

# このアプリは Active Storage のダイレクトアップロードを使わない
# (config/initializers/active_storage_direct_uploads.rb)。
# 画像の受け付けは Api::Admin::ImagesController (管理者のみ) に限る。
RSpec.describe 'ActiveStorage direct uploads', type: :request do
  let(:blob_params) do
    {
      blob: {
        filename: 'x.html',
        byte_size: 11,
        checksum: 'XrY7u+Ae7tCTyyK7j1rNww==',
        content_type: 'text/html'
      }
    }
  end

  describe 'POST /rails/active_storage/direct_uploads' do
    it '404 を返し、blob を作らず、アップロード先の URL も返さないこと' do
      expect do
        post '/rails/active_storage/direct_uploads', params: blob_params, as: :json
      end.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:not_found)
      expect(response.body).to be_blank
    end

    it '管理者としてログインしていても受け付けないこと (入口自体を使わない)' do
      Admin.create!(email: 'admin@example.com', password: 'password12345', password_confirmation: 'password12345')
      post '/api/auth/sign_in',
           params: { admin: { email: 'admin@example.com', password: 'password12345' } },
           as: :json
      token = response.headers['Authorization']

      expect do
        post '/rails/active_storage/direct_uploads',
             params: blob_params, headers: { 'Authorization' => token }, as: :json
      end.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe '既存の画像の配信 (影響を受けないこと)' do
    it 'アップロード済みの blob の URL は、これまでどおりリダイレクトを返すこと' do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: Rails.root.join('spec/fixtures/files/test_image.jpg').open,
        filename: 'test_image.jpg',
        content_type: 'image/jpeg'
      )

      get Rails.application.routes.url_helpers.rails_blob_path(blob, only_path: true)

      expect(response).to have_http_status(:found)
    end
  end
end
