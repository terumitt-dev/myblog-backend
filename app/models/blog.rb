# frozen_string_literal: true

require "nkf"
require "cgi"

class Blog < ApplicationRecord
  has_many :comments, dependent: :destroy
  has_many_attached :images
  validates :title, :category, :content, presence: true
  enum :category, { uncategorized: 0, hobby: 1, tech: 2, other: 3 }, default: :uncategorized

  SAFE_TAGS = %w[p br h1 h2 h3 h4 h5 h6 a img figure figcaption ul ol li blockquote pre code em strong].freeze
  SAFE_ATTRIBUTES = %w[href src alt width height class target rel loading].freeze

  MAX_UPLOAD_SIZE = 5.megabytes
  ALLOWED_EXTENSIONS = %w[.txt]
  ALLOWED_MIME_TYPES = %w[text/plain]
  MAX_ENTRIES_COUNT = 1000
  MAX_ENTRY_SIZE = 100.kilobytes

  # ファイルバリデーション
  def self.valid_mt_file?(uploaded_file)
    return false unless uploaded_file
    return false if uploaded_file.size.zero?

    ext = File.extname(uploaded_file.original_filename.to_s).downcase

    # MIME判定
    mime_detection_failed = false
    begin
      mime = Marcel::MimeType.for(uploaded_file, name: uploaded_file.original_filename) || ""
      uploaded_file.rewind

      if mime.empty?
        Rails.logger.info "MIME detection returned empty for uploaded file, using extension-only check"
        mime_detection_failed = true
      end
    rescue StandardError => e
      Rails.logger.info "MIME detection failed for uploaded file: #{e.class.name}, using extension-only check"
      mime_detection_failed = true
    end

    ext_ok  = ALLOWED_EXTENSIONS.include?(ext)
    mime_ok = ALLOWED_MIME_TYPES.include?(mime)

    # 基本バリデーション
    base_valid = if mime_detection_failed
      ext_ok
    else
      ext_ok && mime_ok
    end

    # セキュリティのため常時内容妥当性をチェック
    base_valid && valid_text_content?(uploaded_file)
  end

  # テキストファイルの内容妥当性チェック
  def self.valid_text_content?(uploaded_file)
    sample = uploaded_file.read(2048)
    uploaded_file.rewind

    return false if sample.empty?

    # NKF変換してからUTF-8エンコーディング確認
    begin
      utf8_sample = NKF.nkf("-w", sample)
      return false unless utf8_sample.valid_encoding?
    rescue
      return false
    end

    # 危険な制御文字の存在チェック（NULL文字など）
    dangerous_chars = utf8_sample.count("\x00-\x08\x0B\x0C\x0E-\x1F\x7F")
    return false if dangerous_chars > 0

    # 印刷可能文字の比率を厳格化（95%以上が妥当な文字）
    printable_chars = utf8_sample.count(" -~\t\n\r") + utf8_sample.scan(/[^\x00-\x7F]/).size
    printable_ratio = printable_chars.to_f / utf8_sample.size
    printable_ratio > 0.90
  end

  # --- MTファイルからのインポート ---
  # 呼び出し元(コントローラ)でvalid_mt_file?によるバリデーション済みであっても、防御的に再検証する
  def self.import_from_mt(uploaded_file)
    uploaded_file.rewind if uploaded_file.respond_to?(:rewind)
    return { success: 0, errors: [], error_type: :invalid_file } unless valid_mt_file?(uploaded_file)
    uploaded_file.rewind if uploaded_file.respond_to?(:rewind)

    content = nil
    begin
      content = NKF.nkf("-w", uploaded_file.read)
    rescue => e
      Rails.logger.warn "⚠️ Failed to convert MT file to UTF-8: #{e.message}"
      return { success: 0, errors: ["File encoding conversion failed"], error_type: :encoding_error }
    ensure
      uploaded_file.rewind
    end

    # BOM除去
    content.sub!(/\A\uFEFF/, "")

    entries = parse_mt_content(content)
    if entries.empty?
      return { success: 0, errors: ["No valid entries found in file"], error_type: :no_entries }
    end

    # エントリ数上限チェック
    if entries.size > MAX_ENTRIES_COUNT
      Rails.logger.warn "⚠️ Too many entries: #{entries.size} (max: #{MAX_ENTRIES_COUNT})"
      return { success: 0, errors: ["Too many entries in file (max: #{MAX_ENTRIES_COUNT})"], error_type: :too_many_entries }
    end

    import_result = { success: 0, errors: [] }

    entries.each_slice(50).with_index do |batch, batch_num|
      total_batches = (entries.size / 50.0).ceil
      Rails.logger.info "Processing batch #{batch_num + 1}/#{total_batches} (#{batch.size} entries)"

      # Phase 1: トランザクション外で画像ダウンロード・属性準備
      prepared_entries = []
      batch.each_with_index do |entry, batch_index|
        global_index = batch_num * 50 + batch_index

        blog = Blog.new
        begin
          attributes = blog.prepare_mt_attributes(entry, global_index)
          blog.assign_attributes(attributes)

          # 外部画像をダウンロードしてActive Storageに保存、URLを書き換え（HTTP通信はトランザクション外）
          blog.content = blog.rewrite_external_images!(blog.content)

          prepared_entries << { blog: blog, index: global_index }
        rescue StandardError => e
          blog.images.blobs.each(&:purge_later) if blog.images.attached?
          Rails.logger.warn "Entry #{global_index + 1}: Preparation failed (#{e.class.name})"
          import_result[:errors] << "Entry #{global_index + 1}: Preparation failed"
        end
      end

      # Phase 2: トランザクション内でDB保存のみ
      begin
        Blog.transaction do
          prepared_entries.each do |prepared|
            begin
              prepared[:blog].save!
              import_result[:success] += 1
              Rails.logger.debug "Entry #{prepared[:index] + 1}: Successfully imported"
            rescue ActiveRecord::RecordInvalid => e
              prepared[:blog].images.blobs.each(&:purge_later)
              Rails.logger.warn "Entry #{prepared[:index] + 1}: Validation failed (#{e.record.errors.count} validation errors)"
              import_result[:errors] << "Entry #{prepared[:index] + 1}: Validation failed"
            rescue StandardError => e
              prepared[:blog].images.blobs.each(&:purge_later)
              Rails.logger.warn "Entry #{prepared[:index] + 1}: Import failed (#{e.class.name})"
              import_result[:errors] << "Entry #{prepared[:index] + 1}: Import failed"
            end
          end
        end
      rescue => e
        Rails.logger.error "Batch #{batch_num + 1}: Transaction failed - #{e.message}"
        import_result[:errors] << "Batch #{batch_num + 1}: Transaction failed"
      end
    end

    import_result
  end

  # --- MTパース（堅牢化） ---
  def self.parse_mt_content(content)
    entries = []

    # より堅牢な区切り文字でエントリを分割
    entry_blocks = content.split(/\r?\n-{5,}\r?\n/)

    entry_blocks.each_with_index do |block, index|
      next if block.strip.empty?

      begin
        entry = parse_mt_entry_block(block.strip)
        entries << entry if entry
      rescue => e
        Rails.logger.warn "⚠️ Failed to parse entry block #{index + 1} (#{e.class.name})"
        next
      end
    end

    # 従来の正規表現方式もフォールバック
    if entries.empty?
      content.scan(
        /AUTHOR:\s*(.*?)\r?\nTITLE:\s*(.*?)\r?\n(?:.*?\r?\n)*?DATE:\s*(.*?)\r?\n(?:.*?\r?\n)*?BODY:\r?\n(.*?)(?:\r?\n-{3,}\r?\n|\z)/m
      ) do |_author, title, date, body|
        entries << {
          title: title.to_s.strip,
          content: body.to_s.gsub(/\r\n?/, "\n").strip,
          date: date.to_s.strip
        }
      end
    end

    entries
  end

  # --- MTエントリブロックのパース（フィールド順序に依存しない） ---
  def self.parse_mt_entry_block(block)
    fields = {}
    current_field = nil
    current_content = []

    block.split(/\r?\n/).each do |line|
      if line =~ /^([A-Z]+):\s*(.*)$/
        # 前のフィールドを保存
        if current_field
          fields[current_field.downcase.to_sym] = current_content.join("\n").strip
        end
        # 新しいフィールドを開始
        current_field = $1
        current_content = [$2]
      elsif current_field
        current_content << line
      end
    end

    # 最後のフィールドを保存
    if current_field
      fields[current_field.downcase.to_sym] = current_content.join("\n").strip
    end

    # 必須フィールドチェック
    return nil unless fields[:title] && fields[:body]

    {
      title: fields[:title],
      content: fields[:body].gsub(/\r\n?/, "\n"),
      date: fields[:date] || ""
    }
  end

  # MTエントリデータから個別レコードの属性を準備
  def prepare_mt_attributes(entry, index)
    safe_title = sanitize_title(entry[:title])
    safe_content = sanitize_content(entry[:content])

    # 空データチェック
    if safe_title.blank? || safe_content.blank?
      Rails.logger.info "Entry #{index + 1}: Skipped due to empty title or content"
      raise "Entry #{index + 1}: Empty title or content"
    end

    # エントリサイズチェック
    entry_size = safe_title.bytesize + safe_content.bytesize
    if entry_size > MAX_ENTRY_SIZE
      Rails.logger.warn "⚠️ Entry #{index + 1} too large: #{entry_size} bytes"
      raise "Entry #{index + 1}: Content too large (#{entry_size} bytes)"
    end

    date = parse_mt_date(entry[:date])
    now = Time.zone.now

    {
      title: safe_title,
      content: safe_content,
      category: :uncategorized,
      created_at: date,
      updated_at: now
    }
  end

  # フロントエンドの記事詳細ページの公開URL（X連携でツイートに含めるURL）
  def public_url
    host = ENV.fetch("APP_HOST", "localhost:3000")
    "https://#{host}/posts/#{id}"
  end

  # content内の外部画像をダウンロードしてActive Storageに保存し、URLを書き換える
  def rewrite_external_images!(html)
    return html if html.blank?

    doc = Nokogiri::HTML.fragment(html)
    doc.css("img").each do |img|
      src = img["src"]
      next if src.blank?

      new_url = ImageDownloader.download_and_attach(src, self)
      img["src"] = new_url if new_url
    end

    doc.to_html
  end

  private

  # タイトル用サニタイズ（全タグ除去）
  def sanitize_title(text)
    unescaped = CGI.unescapeHTML(text.to_s)
    ActionController::Base.helpers.sanitize(unescaped, tags: []).gsub('&nbsp;', ' ').strip
  end

  # コンテンツ用サニタイズ（安全なタグを残す）
  def sanitize_content(text)
    unescaped = CGI.unescapeHTML(text.to_s)
    ActionController::Base.helpers.sanitize(unescaped, tags: SAFE_TAGS, attributes: SAFE_ATTRIBUTES)
      .gsub('&nbsp;', ' ').strip
  end

  # 日付パース（複数フォーマット対応）（インスタンスメソッド）
  def parse_mt_date(date_str)
    return Time.zone.now if date_str.blank?

    formats = [
      "%m/%d/%Y %H:%M:%S",
      "%Y-%m-%d %H:%M:%S",
      "%Y/%m/%d %H:%M:%S",
      "%a %b %d %H:%M:%S %Y"
    ]

    formats.each do |fmt|
      begin
        return Time.zone.strptime(date_str, fmt)
      rescue ArgumentError
        next
      end
    end

    begin
      parsed = Time.zone.parse(date_str)
      return parsed if parsed.present?
    rescue => e
      Rails.logger.warn "⚠️ Time.zone.parse also failed: #{date_str} (#{e.message})"
    end

    Rails.logger.warn "⚠️ DATE parse failed, fallback to now: #{date_str}"
    Time.zone.now
  end
end
