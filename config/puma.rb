# frozen_string_literal: true

# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch('RAILS_MAX_THREADS', 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch('PORT', 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# SolidQueue worker を Puma 同一プロセスで実行する (in-process supervisor)。
# 個人ブログ規模では別 worker Pod は不要、Puma plugin で十分。
# 本番では常に有効化、それ以外では SOLID_QUEUE_IN_PUMA を立てたときのみ。
#
# 環境判定は RAILS_ENV / RACK_ENV のいずれかが production なら有効化する。
# - RAILS_ENV / RACK_ENV のどちらかしか渡らない構成への対応
# - 両方セットされていて値が食い違う場合 (RAILS_ENV=development かつ
#   RACK_ENV=production 等) でも片方が production なら solid_queue を起動する
#   ことで、ジョブが永遠に処理されない事故を防ぐ
production_envs = [ENV['RAILS_ENV'], ENV['RACK_ENV']].compact

# SOLID_QUEUE_IN_PUMA は env 文字列として渡るため、Ruby の truthy 判定をそのまま
# 使うと "false" や "0" でも有効化されてしまう (Ruby では nil/false 以外は全て truthy)。
# 明示的に「真とみなす値」のみ受け付けることで、env 設定ミスで意図せず in-process
# worker が起動して二重実行や DB 負荷増を招くのを防ぐ。
solid_queue_in_puma_enabled =
  %w[1 true yes on].include?(ENV['SOLID_QUEUE_IN_PUMA'].to_s.downcase)

if production_envs.include?('production') || solid_queue_in_puma_enabled
  plugin :solid_queue

  # SolidQueue を Puma プロセス内のスレッドで動かす (async)。
  # 既定の fork だと supervisor / worker / dispatcher / scheduler が別プロセスになり、
  # Puma と合わせて 5 プロセスがそれぞれ Rails を抱える。本番のメモリ上限 (384Mi) を
  # 起動直後からほぼ使い切り、約20分で応答不能 → liveness probe による再起動を
  # 繰り返していた (2026-11)。ジョブはリセットメールとツイート通知だけなので、
  # プロセス分離は不要。問題が出た場合は SOLID_QUEUE_MODE=fork で元に戻せる。
  # async ではジョブ用スレッドも Puma と同じ DB コネクションプールを使うため、
  # config/database.yml の pool をその分だけ広げている。
  solid_queue_mode ENV.fetch('SOLID_QUEUE_MODE', 'async')
end

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV['PIDFILE'] if ENV['PIDFILE']
