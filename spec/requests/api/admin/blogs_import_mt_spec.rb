# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::Admin::Blogs#import_mt', type: :request do
  let(:admin) { Admin.create!(email: 'admin@example.com', password: 'password123', password_confirmation: 'password123') }

  let(:token) do
    post '/api/auth/sign_in',
         params: { admin: { email: admin.email, password: 'password123' } },
         as: :json
    response.headers['Authorization']
  end

  def upload_txt(content)
    temp_file = Tempfile.new(['mt_import', '.txt'])
    temp_file.write(content)
    temp_file.rewind
    yield Rack::Test::UploadedFile.new(temp_file.path, 'text/plain')
  ensure
    temp_file.close
    temp_file.unlink
  end

  describe 'POST /api/admin/blogs/import_mt' do
    context '認証されている場合' do
      it '有効なMTファイルでブログが作成され、成功件数を返すこと' do
        mt_content = <<~MT
          AUTHOR: admin
          TITLE: サンプルブログ
          DATE: 09/27/2025 14:00:00
          BODY:
          こんにちは
          -----
        MT

        expect do
          upload_txt(mt_content) do |file|
            post '/api/admin/blogs/import_mt', params: { file: file }, headers: { 'Authorization' => token }
          end
        end.to change(Blog, :count).by(1)

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['success']).to eq(1)
        expect(json['errors']).to eq(0)
      end

      it '無効な内容のファイルではブログが作成されず、422を返すこと' do
        expect do
          upload_txt('無効な内容') do |file|
            post '/api/admin/blogs/import_mt', params: { file: file }, headers: { 'Authorization' => token }
          end
        end.not_to change(Blog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'MIMEタイプが不正なファイルは弾かれること' do
        allow(Marcel::MimeType).to receive(:for).and_return('application/octet-stream')

        expect do
          upload_txt("AUTHOR: admin\nTITLE: t\nDATE: 09/27/2025\nBODY:\nhi\n-----\n") do |file|
            post '/api/admin/blogs/import_mt', params: { file: file }, headers: { 'Authorization' => token }
          end
        end.not_to change(Blog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it '空ファイルは弾かれること' do
        expect do
          upload_txt('') do |file|
            post '/api/admin/blogs/import_mt', params: { file: file }, headers: { 'Authorization' => token }
          end
        end.not_to change(Blog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'サイズ上限を超えたファイルは弾かれること' do
        large_content = 'a' * (Blog::MAX_UPLOAD_SIZE + 1)

        expect do
          upload_txt(large_content) do |file|
            post '/api/admin/blogs/import_mt', params: { file: file }, headers: { 'Authorization' => token }
          end
        end.not_to change(Blog, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'ファイルが指定されない場合、422を返すこと' do
        post '/api/admin/blogs/import_mt', params: {}, headers: { 'Authorization' => token }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context '認証されていない場合' do
      it '401を返すこと' do
        upload_txt("AUTHOR: admin\nTITLE: t\nDATE: 09/27/2025\nBODY:\nhi\n-----\n") do |file|
          post '/api/admin/blogs/import_mt', params: { file: file }
        end

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
