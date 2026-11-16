# My Blog — Backend

個人ブログプラットフォームの API バックエンド。
Rails 8（API モード）で構築し、JWT 認証、ActiveStorage によるS3画像管理、HTMLサニタイズ、レートリミット、X（旧 Twitter）への投稿連携などを実装しています。

<!-- TODO: API レスポンスのスクリーンショットや構成図を貼る -->

## 技術スタック

| カテゴリ | 技術 |
|---|---|
| フレームワーク | Ruby on Rails 8.1（API モード） |
| 言語 | Ruby 4.0 |
| データベース | PostgreSQL |
| 認証 | Devise + devise-jwt（JWT） |
| ファイルストレージ | ActiveStorage + AWS S3 |
| アプリケーションサーバー | Puma |
| バックグラウンドジョブ | Solid Queue（Puma プロセス内で実行） |
| キャッシュ | Solid Cache（レートリミットのカウンタにも使用） |
| レートリミット | Rack::Attack |
| テスト | RSpec + FactoryBot |
| リンター | RuboCop（Rails / RSpec / FactoryBot プラグイン） |
| コンテナ | Docker（multi-stage build） |
| CI/CD | Drone CI → AWS ECR |

## API 設計

### パブリックエンドポイント（認証不要）

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/blogs` | 記事一覧（ページネーション・カテゴリフィルタ対応） |
| GET | `/api/blogs/:id` | 記事詳細 |
| GET | `/api/blogs/:blog_id/comments` | コメント一覧 |
| POST | `/api/blogs/:blog_id/comments` | コメント投稿 |

### 認証エンドポイント

| メソッド | パス | 説明 |
|---|---|---|
| POST | `/api/auth/sign_up` | 管理者登録（サインアップパスワード必須） |
| POST | `/api/auth/sign_in` | ログイン（JWT 発行） |
| DELETE | `/api/auth/sign_out` | ログアウト（JWT 失効） |
| GET | `/api/auth/current_user` | ログイン中の管理者情報（JWT 認証必須） |
| POST | `/api/auth/password` | パスワードリセットメール送信（`PASSWORD_RESET_SECRET` 必須） |
| PATCH | `/api/auth/password` | パスワードリセット実行（メールのトークン必須） |

### 管理者エンドポイント（JWT 認証必須）

| メソッド | パス | 説明 |
|---|---|---|
| GET/POST/PATCH/DELETE | `/api/admin/blogs/*` | 記事 CRUD |
| POST | `/api/admin/blogs/import_mt` | Movable Type 形式インポート |
| POST | `/api/admin/blogs/:id/tweet` | 記事を X に投稿（自動投稿が失敗したときの手動リトライ） |
| POST | `/api/admin/images` | 画像アップロード |
| POST | `/api/admin/x/connect` | X 連携（OAuth）の開始。X の認可画面の URL を返す |

### X 連携のコールバック

| メソッド | パス | 説明 |
|---|---|---|
| GET | `/api/admin/x/callback` | X の認可画面からの戻り先。ブラウザの遷移では JWT を送れないため JWT 認証の対象外とし、連携を始めたブラウザだけが持つ暗号化 Cookie で照合する |

## アーキテクチャ

### ディレクトリ構成

```
app/
├── controllers/
│   ├── application_controller.rb       # API ベースコントローラー
│   ├── concerns/
│   │   └── x_connect_state_cookie.rb   # X 連携の state を暗号化 Cookie で保持
│   └── api/
│       ├── auth/                       # 認証（Devise カスタム）
│       │   ├── registrations_controller.rb
│       │   ├── sessions_controller.rb
│       │   ├── current_users_controller.rb
│       │   └── passwords_controller.rb # パスワードリセット
│       ├── blogs_controller.rb         # パブリック記事 API
│       ├── comments_controller.rb      # コメント API
│       ├── x_callbacks_controller.rb   # X 連携のコールバック
│       └── admin/
│           ├── blogs_controller.rb     # 管理者 CRUD + MT インポート + X 投稿
│           ├── images_controller.rb    # 画像アップロード
│           └── x_connections_controller.rb # X 連携の開始
├── jobs/
│   ├── password_reset_request_job.rb   # リセットメール送信
│   └── tweet_notification_job.rb       # 記事作成時の X 自動投稿
├── models/
│   ├── blog.rb                         # 記事（カテゴリ enum, 画像添付）
│   ├── comment.rb                      # コメント
│   ├── admin.rb                        # 管理者（1インスタンス1人制限）
│   └── jwt_blacklist.rb                # JWT 失効管理
└── services/
    ├── dispatch_client.rb              # myblog-dispatch（X 連携サービス）の呼び出し
    ├── image_downloader.rb             # 外部画像ダウンロード（MT インポート用）
    └── turnstile_service.rb            # Cloudflare Turnstile token 検証
```

### データベース設計

```
blogs
├── title        : string
├── content      : text（HTMLサニタイズ済み）
├── category     : integer（enum: uncategorized/hobby/tech/other）
└── timestamps

comments
├── blog_id      : references
├── user_name    : string（50文字まで）
├── comment      : text（2000文字まで）
└── timestamps

admins
├── email        : string（Devise）
├── encrypted_password
└── reset_password_token / reset_password_sent_at

jwt_blacklists
├── jti          : string（トークン識別子）
└── exp          : datetime（有効期限）

+ ActiveStorage テーブル（画像管理）
+ Solid Queue / Solid Cache テーブル（ジョブ・キャッシュ）
```

### 認証フロー

```
ログイン
  → POST /api/auth/sign_in（email + password）
  → JWT 発行（Authorization ヘッダーで返却、有効期限1時間）
  → クライアントは以降のリクエストで Authorization: Bearer <token> を付与

ログアウト
  → DELETE /api/auth/sign_out
  → JWT を jwt_blacklists テーブルに登録（以降無効化）
```

## キャッシュ戦略

全エンドポイントで `Cache-Control` ヘッダーを明示的に制御し、CDN（Cloudflare 等）の意図しないキャッシュ事故を防いでいます。

### 戦略

| エンドポイント | Cache-Control | 目的 |
|---|---|---|
| `GET /api/blogs` | `public, s-maxage=300, max-age=0` | CDN は5分キャッシュ、ブラウザは毎回確認 |
| `GET /api/blogs/:id` | 同上 | 同上 |
| `GET /api/blogs/:id/comments` | 同上 | 同上 |
| 上記以外（認証・変更・管理系） | `no-store` | 一切キャッシュしない |

### 設計の意図

- **デフォルト `no-store`**: `ApplicationController#set_default_cache_control` で全エンドポイントに適用。新しい API 追加時の事故を防ぐ安全側設計。
- **パブリック GET のみ明示的に上書き**: `set_cdn_cacheable` を `before_action` で指定する形で許可フラグを立てる。
- **`after_action` で実際のヘッダーを付与**: エラー応答（4xx/5xx）や認証付きリクエストをキャッシュ対象から除外。成功した匿名 GET のみ `public` として扱う。
- **`Vary: Authorization, Cookie`**: 認証情報ごとに別キャッシュエントリとして扱われるため、個人化レスポンスの共有キャッシュ混入を防止。
- **`s-maxage=300 + max-age=0` の組み合わせ**: CDN には5分間キャッシュを許可しつつ、ブラウザにはキャッシュさせない。記事更新時、最大5分で全ユーザーに反映。
- **CDN 非依存**: `Cache-Control` は HTTP 標準ヘッダーなので、Cloudflare / CloudFront / Fastly など CDN を切り替えても同じ戦略が機能する。

## セキュリティ

| 対策 | 実装 |
|---|---|
| 認証 | JWT（Devise + devise-jwt）、1時間有効期限 |
| JWT 失効 | ブラックリスト方式（ログアウト時に jti を DB 登録） |
| 管理者制限 | インスタンスあたり1人のみ（モデルバリデーション） |
| 登録保護 | `ADMIN_SIGNUP_PASSWORD` 環境変数による招待制 |
| レートリミット | Rack::Attack。ログイン・管理者登録・パスワードリセット・コメント投稿を対象（下記） |
| HTML サニタイズ | ホワイトリスト方式（安全なタグ・属性のみ許可） |
| ファイルアップロード | 管理者のみ。MIME タイプ検証（Marcel）、5MB サイズ制限。ActiveStorage のダイレクトアップロードは使わないため 404 で閉じている |
| 外部画像 DL | ホスト許可リスト、MIME 検証、リダイレクト上限（3回） |
| CORS | 環境別オリジン制限（本番はドメイン限定） |
| パスワード | bcrypt（本番12ストレッチ）、12文字以上 |
| コメントの長さ | 名前 50文字 / 本文 2000文字まで（サーバー側で検証） |
| X 連携 | OAuth の state を暗号化 Cookie（HttpOnly / SameSite=Lax / 5分）でブラウザに束縛。認可 URL の宛先を許可リストで検証。`code` / `state` はログに出さない |
| コメント Bot 対策 | Cloudflare Turnstile siteverify（`TurnstileService`）。token 検証 + hostname allow-list + 本番テストキー拒否 |

### レートリミット（Rack::Attack）

`config/initializers/rack_attack.rb` で設定しています。上限を超えたリクエストには `429` と `Retry-After` を返します。カウンタは Solid Cache に保存するため、プロセスや Pod をまたいで共有されます。

| 対象 | 上限 |
|---|---|
| `POST /api/auth/sign_in` | 同一 IP から 10分に 10回 |
| `POST /api/auth/sign_up` | 同一 IP から 1時間に 5回、全体で 1時間に 20回 |
| `POST /api/auth/password` | 同一 IP から 1時間に 5回、全体で 1時間に 20回 |
| `PATCH /api/auth/password` | 同一 IP から 1時間に 10回 |
| `POST /api/blogs/:blog_id/comments` | 同一 IP から 10分に 20回 |

ログインに全体の上限を置いていないのは、第三者が上限まで叩くだけで管理者本人がログインできなくなるのを避けるためです。

### コメント Bot 対策（Cloudflare Turnstile）

コメント投稿（`POST /api/blogs/:blog_id/comments`）は認証不要のため、bot / spam による DB 負荷を防ぐ目的で Cloudflare Turnstile を組み込んでいます。token 検証は backend 側で `Cloudflare siteverify API` を直接叩いて行います。

**全体フロー**

```
ユーザー → frontend (widget 解決 → token 取得)
       → POST /api/blogs/:id/comments (body の top-level に turnstile_token)
       → backend: Api::CommentsController#create
              → verify_turnstile! が TurnstileService.verify を呼ぶ
              → siteverify API で token + hostname を検証
              → 成功なら Comment.create、失敗なら 422 で fail-closed
```

**backend 側の実装** (`app/services/turnstile_service.rb`)

- `Net::HTTP` で `challenges.cloudflare.com/turnstile/v0/siteverify` を直接叩く（gem 追加なし）
- `before_action :verify_turnstile!` が `set_blog` より先に走るため、無効 token のリクエストは DB 参照に到達しない（DB 負荷 + blog_id 列挙の両方をガード）
- 入力検証: `token.is_a?(String)` 型チェック + `MAX_TOKEN_BYTESIZE = 2048` の byte サイズ上限（過大ペイロードを Cloudflare へ転送する増幅攻撃を防止）
- siteverify 応答の `hostname` を `ALLOWED_HOSTNAMES` (allow-list) と照合（多層防御）
- 本番では起動時 fail-fast（`config/application.rb` boot 時）:
  - `TURNSTILE_SECRET_KEY` 未設定 / 空 → boot 失敗
  - 本番で Cloudflare 公開のテストキー（`1x0000...AA` 等）を設定 → boot 失敗（誤デプロイ防止）
  - `TURNSTILE_ALLOWED_HOSTNAMES` 未設定 → boot 失敗（silent な検証無効化を防ぐ）

**dev / test 環境**

`spec/rails_helper.rb` がテスト用の `TURNSTILE_SECRET_KEY` を設定し、スペックでは `TurnstileService.verify` をスタブするため、追加の設定なしでテストが通る。`docker compose up` の dev 環境は、Cloudflare 公開の always-pass テスト Secret Key（`1x0000000000000000000000000000000AA`）を使う。

**関連リポジトリ**

- [`myblog-frontend`](https://github.com/terumitt-dev/myblog-frontend): Turnstile widget の埋め込み（`CommentForm`）
- [`go-lilaregard-ops`](https://github.com/terumitt-dev/go-lilaregard-ops): `TURNSTILE_SECRET_KEY` (Secret) / `TURNSTILE_ALLOWED_HOSTNAMES` (ConfigMap) の K8s 注入

### X（旧 Twitter）連携

記事を作成すると `TweetNotificationJob` が X への投稿を試みます。投稿と OAuth のトークン管理は別サービスの [`myblog-dispatch`](https://github.com/terumitt-dev/myblog-dispatch) が受け持ち、backend はクラスタ内の API（共有キー `DISPATCH_API_KEY`）で呼び出すだけです。

- `DISPATCH_BASE_URL` / `DISPATCH_API_KEY` が未設定の場合、投稿はスキップされます（記事の保存には影響しません）。
- 自動投稿の失敗はログに残るだけで、記事作成のレスポンスには影響しません。管理画面の「ツイート」ボタン（`POST /api/admin/blogs/:id/tweet`）で再実行でき、こちらは成否を返します。
- 連携の開始からコールバックまでは 5分以内に完了させる必要があります（state と Cookie の有効期間）。

### HTML サニタイズの仕組み

記事本文に含まれる HTML を保存時にサニタイズします。

**許可タグ**: `p`, `br`, `h1`-`h6`, `a`, `img`, `figure`, `figcaption`, `ul`, `ol`, `li`, `blockquote`, `pre`, `code`, `em`, `strong`

**許可属性**: `href`, `src`, `alt`, `width`, `height`, `class`, `target`, `rel`, `loading`

ホワイトリストに含まれないタグ・属性は自動的に除去されます。

## テスト

```bash
# テスト実行
bundle exec rspec

# 特定ファイルのみ
bundle exec rspec spec/requests/api/auth_spec.rb
```

- **RSpec** + **FactoryBot** によるテスト
- **モデルテスト**: バリデーション、アソシエーション
- **リクエストテスト**: API エンドポイントの統合テスト（認証、レートリミット、X 連携のコールバックを含む）
- **サービステスト**: ImageDownloader / TurnstileService / DispatchClient
- **ジョブテスト**: TweetNotificationJob

テストには PostgreSQL が必要です。手元に Ruby 4.0 が無い場合は、コンテナ内で実行できます。

```bash
docker run -d --name myblog-test-pg -e POSTGRES_PASSWORD=password -p 55439:5432 postgres:18-alpine

docker run --rm -v "$PWD":/w -w /w \
  -e RAILS_ENV=test -e DATABASE_HOST=host.docker.internal -e DATABASE_PORT=55439 \
  -e DATABASE_USERNAME=postgres -e DATABASE_PASSWORD=password \
  ruby:4.0.9-bookworm sh -c '
    apt-get update -qq && apt-get install -y -qq libvips-dev &&
    bundle install && bin/rails db:create db:schema:load && bundle exec rspec'
```

## デプロイ

### Docker（マルチステージビルド）

```dockerfile
# ステージ1: gem インストール + アセットプリコンパイル
# ステージ2: ruby-slim ベースの軽量ランタイム
```

- 本番イメージは **非root ユーザー**（`rails:rails`）で実行
- ヘルスチェック: `/up` エンドポイントに30秒間隔でリクエスト
- エントリポイント: `bin/docker-entrypoint`（`rails db:prepare` をリトライ付きで実行）
- Solid Queue は Puma と同じプロセス内のスレッドで動かす（`config/puma.rb` の `solid_queue_mode`）。プロセスを分けるとコンテナのメモリ上限を使い切るため。`SOLID_QUEUE_MODE=fork` で別プロセスに戻せる

### CI/CD（Drone）

```
push to main
  → Docker ビルド（Kaniko）
  → ECR push（commit SHA + latest タグ）
  → K8s 上で自動デプロイ（Keel による image digest 検知）

pull request
  → Docker ビルドのみ（push しない）
```

シークレットを参照するステップは main への push のときだけ動きます。CI はイメージのビルドだけを行い、テストは実行しません（マージ前に手元で `bundle exec rspec` を実行する）。

### ActiveStorage（S3）

- **開発環境**: ローカルディスク
- **本番環境**: AWS S3（`go-lilaregard-blog-images` バケット）
- EC2 インスタンスプロファイル経由で IAM 認証（アクセスキー不要）

## 開発環境セットアップ

### 前提条件

- Ruby 4.0（`.ruby-version` を参照）
- PostgreSQL
- Node.js（アセット関連）

### セットアップ

```bash
# gem インストール
bundle install

# DB 作成 + マイグレーション
rails db:create db:migrate

# 開発サーバー起動
rails server
```

### Docker Compose で起動

```bash
docker-compose up -d
```

PostgreSQL + Rails が起動し、`http://localhost:3000` でアクセスできます。

### 主要な環境変数

| 変数 | 説明 |
|---|---|
| `DATABASE_HOST` | DB ホスト |
| `DATABASE_PORT` | DB ポート |
| `DATABASE_USERNAME` | DB ユーザー名 |
| `DATABASE_PASSWORD` | DB パスワード |
| `DATABASE_NAME` | DB 名（本番。既定は `myblog_production`） |
| `SECRET_KEY_BASE` | Rails 暗号化キー |
| `APP_HOST` | 公開ホスト名（本番で必須。スキーム・ポート・パスを含めない） |
| `ADMIN_SIGNUP_PASSWORD` | 管理者登録パスワード |
| `JWT_SECRET_KEY` | JWT 署名キー |
| `PASSWORD_RESET_SECRET` | パスワードリセットメールの送信を要求するための秘密値 |
| `SMTP_USERNAME` | メール送信用 SMTP ユーザー名 |
| `SMTP_PASSWORD` | メール送信用 SMTP パスワード |
| `MAILER_SENDER` | メールの送信元アドレス（本番で必須） |
| `S3_BLOG_IMAGES_BUCKET` | 画像を保存する S3 バケット名（本番で必須） |
| `TURNSTILE_SECRET_KEY` | Cloudflare Turnstile Secret Key |
| `TURNSTILE_ALLOWED_HOSTNAMES` | Turnstile hostname allow-list（カンマ区切り） |
| `DISPATCH_BASE_URL` | myblog-dispatch の URL（未設定なら X への投稿をスキップ） |
| `DISPATCH_API_KEY` | myblog-dispatch を呼び出す共有キー（未設定なら X への投稿をスキップ） |
| `SOLID_QUEUE_MODE` | Solid Queue の動かし方（既定 `async`。`fork` で別プロセス） |
| `DB_POOL` | DB コネクションプールの大きさ（既定は Puma とジョブのスレッド数から計算） |

## 関連リポジトリ

- [myblog-frontend](https://github.com/terumitt-dev/myblog-frontend) — React フロントエンド
- [myblog-dispatch](https://github.com/terumitt-dev/myblog-dispatch) — X 連携サービス（Go）
- [go-lilaregard-ops](https://github.com/terumitt-dev/go-lilaregard-ops) — インフラ・K8s マニフェスト・CD
