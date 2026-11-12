FROM ruby:4.0.9-bookworm

RUN apt-get update && apt-get install -y nodejs postgresql-client libvips-dev --no-install-recommends && rm -rf /var/lib/apt/lists/*

WORKDIR /myblog

COPY Gemfile Gemfile.lock ./
RUN gem install bundler && bundle config --global frozen 1 && bundle install

ENV PATH="/usr/local/bundle/bin:${PATH}"
