# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Admin::Blogs#tweet', type: :request do
  let(:admin) do
    Admin.create!(email: 'admin@example.com', password: 'password123', password_confirmation: 'password123')
  end
  let!(:blog) { FactoryBot.create(:blog) }

  let(:token) do
    post '/api/auth/sign_in',
         params: { admin: { email: admin.email, password: 'password123' } },
         as: :json
    response.headers['Authorization']
  end

  describe 'POST /api/admin/blogs/:id/tweet' do
    context '認証されている場合' do
      it 'ツイート投稿に成功した場合、tweet_idを返すこと' do
        allow(DispatchClient).to receive(:post_tweet).with(title: blog.title, url: blog.public_url)
                                                     .and_return({ 'tweet_id' => '12345' })

        post "/api/admin/blogs/#{blog.id}/tweet", headers: { 'Authorization' => token }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['tweet_id']).to eq('12345')
      end

      it 'X連携が未設定の場合、503を返すこと' do
        allow(DispatchClient).to receive(:post_tweet).and_raise(DispatchClient::ConfigurationMissing, 'not configured')

        post "/api/admin/blogs/#{blog.id}/tweet", headers: { 'Authorization' => token }

        expect(response).to have_http_status(:service_unavailable)
      end

      it 'ツイート投稿に失敗した場合、502を返すこと' do
        allow(DispatchClient).to receive(:post_tweet).and_raise(DispatchClient::RequestFailed, 'boom')

        post "/api/admin/blogs/#{blog.id}/tweet", headers: { 'Authorization' => token }

        expect(response).to have_http_status(:bad_gateway)
      end

      it '存在しないブログIDの場合、404を返すこと' do
        post '/api/admin/blogs/999999/tweet', headers: { 'Authorization' => token }

        expect(response).to have_http_status(:not_found)
      end
    end

    context '認証されていない場合' do
      it '401を返すこと' do
        post "/api/admin/blogs/#{blog.id}/tweet"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
