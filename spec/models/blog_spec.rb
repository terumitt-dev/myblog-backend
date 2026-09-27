# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Blog, type: :model do
  describe 'validations' do
    context 'titleが空の場合' do
      it '無効であること' do
        blog = Blog.new(title: nil)
        expect(blog).to_not be_valid
      end
    end

    context 'categoryが空の場合' do
      it '無効であること' do
        blog = Blog.new(category: nil)
        expect(blog).to_not be_valid
      end
    end

    context 'contentが空の場合' do
      it '無効であること' do
        blog = Blog.new(content: nil)
        expect(blog).to_not be_valid
      end
    end
  end

  describe 'enum' do
    context 'カテゴリー' do
      it '正しいカテゴリーを持つこと' do
        expect(Blog.categories.keys).to match_array(%w[uncategorized hobby tech other])
      end
    end
  end

  describe '.valid_mt_file?' do
    let(:temp_file) { Tempfile.new(['test', '.txt']) }
    after { temp_file.close; temp_file.unlink }

    it 'UTF-8ファイルを正しく処理できること' do
      temp_file.write("TITLE: テストタイトル\nBODY:\nテスト本文")
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'test.txt',
        type: 'text/plain'
      )

      expect(Blog.valid_mt_file?(uploaded_file)).to be true
    end

    it 'SJISファイルを正しく処理できること' do
      # SJISエンコードのテキストを作成
      sjis_text = "TITLE: テストタイトル\nBODY:\nテスト本文".encode('Shift_JIS')
      temp_file.binmode
      temp_file.write(sjis_text)
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'sjis_test.txt',
        type: 'text/plain'
      )

      expect(Blog.valid_mt_file?(uploaded_file)).to be true
    end

    it 'バイナリファイルを拒否すること' do
      # バイナリデータを直接作成
      binary_data = "\xFF\x00\xFE\x00".b
      temp_file.binmode
      temp_file.write(binary_data)
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'binary.txt',
        type: 'text/plain'
      )

      expect(Blog.valid_mt_file?(uploaded_file)).to be false
    end

    it '空ファイルを拒否すること' do
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'empty.txt',
        type: 'text/plain'
      )

      expect(Blog.valid_mt_file?(uploaded_file)).to be false
    end

    it '無効な拡張子を拒否すること' do
      temp_file.write("テスト内容")
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'test.exe',
        type: 'application/octet-stream'
      )

      expect(Blog.valid_mt_file?(uploaded_file)).to be false
    end
  end

  describe '#prepare_mt_attributes' do
    let(:blog) { Blog.new }
    let(:valid_entry) do
      {
        title: 'テストタイトル',
        content: 'テスト内容',
        date: '12/25/2023 15:30:00'
      }
    end

    it '正常なエントリデータを処理できること' do
      attributes = blog.prepare_mt_attributes(valid_entry, 0)

      expect(attributes[:title]).to eq 'テストタイトル'
      expect(attributes[:content]).to eq 'テスト内容'
      expect(attributes[:category]).to eq :uncategorized
      expect(attributes[:created_at]).to be_a(Time)
      expect(attributes[:updated_at]).to be_a(Time)
    end

    it '空タイトル時にエラーを発生すること' do
      entry = valid_entry.merge(title: '')

      expect {
        blog.prepare_mt_attributes(entry, 1)
      }.to raise_error(/Empty title or content/)
    end

    it '空内容時にエラーを発生すること' do
      entry = valid_entry.merge(content: '')

      expect {
        blog.prepare_mt_attributes(entry, 1)
      }.to raise_error(/Empty title or content/)
    end

    it 'サイズ超過時にエラーを発生すること' do
      large_content = 'a' * (Blog::MAX_ENTRY_SIZE + 1)
      entry = valid_entry.merge(content: large_content)

      expect {
        blog.prepare_mt_attributes(entry, 1)
      }.to raise_error(/Content too large/)
    end
  end

  describe '#sanitize_title' do
    let(:blog) { Blog.new }

    it '全てのHTMLタグを除去すること' do
      text = '<script>alert("xss")</script>テスト<b>太字</b>'
      result = blog.send(:sanitize_title, text)
      expect(result).to eq 'alert("xss")テスト太字'
    end

    it 'HTMLエンティティをデコードすること' do
      text = '&lt;div&gt;テスト&lt;/div&gt;'
      result = blog.send(:sanitize_title, text)
      expect(result).to eq 'テスト'
    end

    it '&nbsp;を半角スペースに変換すること' do
      text = 'テスト&nbsp;サンプル&nbsp;文字列'
      result = blog.send(:sanitize_title, text)
      expect(result).to eq 'テスト サンプル 文字列'
    end

    it '前後の空白を除去すること' do
      text = '  テスト内容  '
      result = blog.send(:sanitize_title, text)
      expect(result).to eq 'テスト内容'
    end

    it '&amp;エンティティの処理を確認すること' do
      text = 'テスト&amp;サンプル'
      result = blog.send(:sanitize_title, text)
      # CGI.unescapeHTMLで&に変換され、sanitizeで&amp;に戻る
      expect(result).to eq 'テスト&amp;サンプル'
    end

    it 'imgタグも除去すること' do
      text = 'タイトル<img src="test.jpg">画像付き'
      result = blog.send(:sanitize_title, text)
      expect(result).to eq 'タイトル画像付き'
    end
  end

  describe '#sanitize_content' do
    let(:blog) { Blog.new }

    it '安全なHTMLタグを保持すること' do
      text = '<p>段落</p><img src="test.jpg" alt="テスト"><figure><figcaption>キャプション</figcaption></figure>'
      result = blog.send(:sanitize_content, text)
      expect(result).to include('<p>')
      expect(result).to include('<img')
      expect(result).to include('<figure>')
      expect(result).to include('<figcaption>')
    end

    it 'scriptタグを除去すること' do
      text = '<p>安全</p><script>alert("xss")</script>'
      result = blog.send(:sanitize_content, text)
      expect(result).to include('<p>安全</p>')
      expect(result).not_to include('<script>')
    end

    it 'h1-h6, ul, ol, li, blockquote, pre, code, em, strong タグを保持すること' do
      text = '<h1>見出し</h1><ul><li>項目</li></ul><blockquote>引用</blockquote><pre><code>コード</code></pre><em>強調</em><strong>太字</strong>'
      result = blog.send(:sanitize_content, text)
      expect(result).to include('<h1>')
      expect(result).to include('<ul>')
      expect(result).to include('<li>')
      expect(result).to include('<blockquote>')
      expect(result).to include('<pre>')
      expect(result).to include('<code>')
      expect(result).to include('<em>')
      expect(result).to include('<strong>')
    end

    it '安全な属性を保持すること' do
      text = '<a href="https://example.com" target="_blank" rel="noopener">リンク</a><img src="test.jpg" alt="テスト" width="100" height="100" loading="lazy">'
      result = blog.send(:sanitize_content, text)
      expect(result).to include('href="https://example.com"')
      expect(result).to include('target="_blank"')
      expect(result).to include('src="test.jpg"')
      expect(result).to include('alt="テスト"')
      expect(result).to include('loading="lazy"')
    end

    it '危険な属性を除去すること' do
      text = '<p onclick="alert(1)" style="color:red">テスト</p>'
      result = blog.send(:sanitize_content, text)
      expect(result).not_to include('onclick')
      expect(result).not_to include('style')
      expect(result).to include('<p>テスト</p>')
    end

    it '&nbsp;を半角スペースに変換すること' do
      text = '<p>テスト&nbsp;サンプル</p>'
      result = blog.send(:sanitize_content, text)
      expect(result).to include('テスト サンプル')
    end

    it '前後の空白を除去すること' do
      text = '  <p>テスト内容</p>  '
      result = blog.send(:sanitize_content, text)
      expect(result).to eq '<p>テスト内容</p>'
    end

    it 'iframeタグを除去すること' do
      text = '<p>テスト</p><iframe src="https://evil.com"></iframe>'
      result = blog.send(:sanitize_content, text)
      expect(result).to include('<p>テスト</p>')
      expect(result).not_to include('<iframe')
    end
  end

  describe '#parse_mt_date' do
    let(:blog) { Blog.new }

    it '複数の日付フォーマットを解析できること' do
      formats = [
        '12/25/2023 15:30:00',
        '2023-12-25 15:30:00',
        '2023/12/25 15:30:00'
      ]

      formats.each do |date_str|
        result = blog.send(:parse_mt_date, date_str)
        expect(result).to be_a(Time)
        expect(result.year).to eq 2023
        expect(result.month).to eq 12
        expect(result.day).to eq 25
      end
    end

    it '無効な日付で現在時刻を返すこと' do
      allow(Time.zone).to receive(:now).and_return(Time.zone.parse('2024-01-01 12:00:00'))

      result = blog.send(:parse_mt_date, '無効な日付')
      expect(result).to eq Time.zone.parse('2024-01-01 12:00:00')
    end

    it '空文字列で現在時刻を返すこと' do
      allow(Time.zone).to receive(:now).and_return(Time.zone.parse('2024-01-01 12:00:00'))

      result = blog.send(:parse_mt_date, '')
      expect(result).to eq Time.zone.parse('2024-01-01 12:00:00')
    end
  end

  describe '.import_from_mt' do
    let(:temp_file) { Tempfile.new(['sample', '.txt']) }
    after { temp_file.close; temp_file.unlink }

    it '正しいMTファイルでブログが作成されること' do
      temp_file.write("AUTHOR: test\nTITLE: サンプルブログ\nDATE: 12/17/2024 19:00:00\nBODY:\n本文です\n-----\n")
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'sample.txt',
        type: 'text/plain'
      )

      expect(Blog.valid_mt_file?(uploaded_file)).to be true

      expect {
        Blog.import_from_mt(uploaded_file)
      }.to change(Blog, :count).by(1)

      blog = Blog.last
      expect(blog.title).to eq 'サンプルブログ'
      expect(blog.content).to eq '本文です'
    end

    it '複数エントリを正しく処理できること' do
      mt_content = <<~MT
        AUTHOR: author1
        TITLE: ブログ1
        DATE: 12/25/2023 15:30:00
        BODY:
        内容1
        -----
        AUTHOR: author2
        TITLE: ブログ2
        DATE: 12/26/2023 16:00:00
        BODY:
        内容2
        -----
      MT

      temp_file.write(mt_content)
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'multiple.txt',
        type: 'text/plain'
      )

      expect {
        result = Blog.import_from_mt(uploaded_file)
        expect(result[:success]).to eq 2
        expect(result[:errors]).to be_empty
      }.to change(Blog, :count).by(2)
    end

    it '無効なMTファイルではブログが作成されないこと' do
      temp_file.write("無効な内容")
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'invalid.txt',
        type: 'text/plain'
      )

      expect {
        result = Blog.import_from_mt(uploaded_file)
        expect(result[:success]).to eq 0
        expect(result[:errors]).not_to be_empty
      }.to_not change(Blog, :count)
    end

    it 'バリデーションエラー時に適切な結果を返すこと' do
      # タイトルが空のエントリ
      mt_content = "AUTHOR: test\nTITLE: \nDATE: 12/25/2023 15:30:00\nBODY:\n内容\n-----\n"

      temp_file.write(mt_content)
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'validation_error.txt',
        type: 'text/plain'
      )

      result = Blog.import_from_mt(uploaded_file)
      expect(result[:success]).to eq 0
      expect(result[:errors].size).to eq 1
    end

    it 'エラー時にログが適切に出力されること' do
      # エラーを発生させるエントリ（空のタイトルと内容）
      mt_content = "AUTHOR: test\nTITLE: \nDATE: 12/25/2023 15:30:00\nBODY:\n\n-----\n"

      temp_file.write(mt_content)
      temp_file.rewind

      uploaded_file = ActionDispatch::Http::UploadedFile.new(
        tempfile: temp_file,
        filename: 'error_test.txt',
        type: 'text/plain'
      )

      # ログ出力の確認（個人情報を含まない形式）
      expect(Rails.logger).to receive(:warn).with(/Entry \d+: Preparation failed \(RuntimeError\)/)

      Blog.import_from_mt(uploaded_file)
    end
  end

  describe '#rewrite_external_images!' do
    let(:blog) { Blog.new(title: 'テスト', category: :tech, content: '本文') }

    it '空のHTMLではそのまま返すこと' do
      expect(blog.rewrite_external_images!('')).to eq ''
      expect(blog.rewrite_external_images!(nil)).to be_nil
    end

    it '画像のないHTMLではそのまま返すこと' do
      html = '<p>テスト本文</p>'
      result = blog.rewrite_external_images!(html)
      expect(result).to include('<p>テスト本文</p>')
    end

    it '外部画像のURLをImageDownloaderで書き換えること' do
      html = '<p><img src="https://cdn-ak.f.st-hatena.com/images/test.jpg"></p>'
      allow(ImageDownloader).to receive(:download_and_attach).and_return('/rails/active_storage/blobs/xxx/test.jpg')

      result = blog.rewrite_external_images!(html)
      expect(result).to include('src="/rails/active_storage/blobs/xxx/test.jpg"')
      expect(ImageDownloader).to have_received(:download_and_attach).once
    end

    it 'ImageDownloaderがnilを返した場合は元のURLを維持すること' do
      html = '<p><img src="https://cdn-ak.f.st-hatena.com/images/test.jpg"></p>'
      allow(ImageDownloader).to receive(:download_and_attach).and_return(nil)

      result = blog.rewrite_external_images!(html)
      expect(result).to include('src="https://cdn-ak.f.st-hatena.com/images/test.jpg"')
    end
  end

  describe '#public_url' do
    let(:blog) { FactoryBot.create(:blog) }

    around do |example|
      original_app_host = ENV['APP_HOST']
      example.run
    ensure
      ENV['APP_HOST'] = original_app_host
    end

    it 'APP_HOSTを使って記事詳細ページのURLを組み立てること' do
      ENV['APP_HOST'] = 'go-lilaregard.com'

      expect(blog.public_url).to eq("https://go-lilaregard.com/posts/#{blog.id}")
    end

    it 'APP_HOSTが未設定の場合はlocalhost:3000にフォールバックすること' do
      ENV['APP_HOST'] = nil

      expect(blog.public_url).to eq("https://localhost:3000/posts/#{blog.id}")
    end
  end
end
