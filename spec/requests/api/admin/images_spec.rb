# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Admin::Images', type: :request do
  let(:admin) { Admin.create!(email: 'admin@example.com', password: 'password12345', password_confirmation: 'password12345') }

  let(:token) do
    post '/api/auth/sign_in',
         params: { admin: { email: admin.email, password: 'password12345' } },
         as: :json
    response.headers['Authorization']
  end

  describe 'POST /api/admin/images' do
    context '認証されている場合' do
      context '有効な画像の場合' do
        it '画像がアップロードされURLが返されること' do
          image = fixture_file_upload(
            Rails.root.join('spec', 'fixtures', 'files', 'test_image.jpg'),
            'image/jpeg'
          )

          post '/api/admin/images',
               params: { image: image },
               headers: { 'Authorization' => token }

          expect(response).to have_http_status(:created)
          json = JSON.parse(response.body)
          expect(json['url']).to be_present
          expect(json['filename']).to eq('test_image.jpg')
        end
      end

      context '画像が提供されない場合' do
        it 'エラーを返すこと' do
          post '/api/admin/images',
               params: {},
               headers: { 'Authorization' => token }

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['error']).to eq('No image provided')
        end
      end

      context '無効なファイル形式の場合' do
        it 'エラーを返すこと' do
          file = fixture_file_upload(
            Rails.root.join('spec', 'fixtures', 'files', 'test.txt'),
            'text/plain'
          )

          post '/api/admin/images',
               params: { image: file },
               headers: { 'Authorization' => token }

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)
          expect(json['error']).to include('Invalid image format')
        end
      end
    end

    context '認証されていない場合' do
      it '401を返すこと' do
        post '/api/admin/images', params: {}, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
