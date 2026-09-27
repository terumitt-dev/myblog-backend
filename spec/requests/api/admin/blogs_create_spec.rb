# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Admin::Blogs#create', type: :request do
  let(:admin) do
    Admin.create!(email: 'admin@example.com', password: 'password123', password_confirmation: 'password123')
  end

  let(:token) do
    post '/api/auth/sign_in',
         params: { admin: { email: admin.email, password: 'password123' } },
         as: :json
    response.headers['Authorization']
  end

  let(:valid_params) { { blog: { title: 'タイトル', category: 'hobby', content: '本文' } } }

  describe 'POST /api/admin/blogs' do
    context '認証されている場合' do
      it '記事の作成に成功した場合、TweetNotificationJobがエンキューされること' do
        expect do
          post '/api/admin/blogs', params: valid_params, headers: { 'Authorization' => token }
        end.to have_enqueued_job(TweetNotificationJob).with(blog_id: kind_of(Integer))

        expect(response).to have_http_status(:created)
      end

      it 'ジョブのエンキューが例外を発生させても、記事作成のレスポンスには影響しないこと' do
        allow(TweetNotificationJob).to receive(:perform_later).and_raise(StandardError, 'queue down')

        post '/api/admin/blogs', params: valid_params, headers: { 'Authorization' => token }

        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json['title']).to eq('タイトル')
      end

      it '記事の作成に失敗した場合、TweetNotificationJobはエンキューされないこと' do
        invalid_params = { blog: { title: '', category: 'hobby', content: '本文' } }

        expect do
          post '/api/admin/blogs', params: invalid_params, headers: { 'Authorization' => token }
        end.not_to have_enqueued_job(TweetNotificationJob)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
