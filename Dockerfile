# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=3.4.5
FROM docker.io/library/ruby:$RUBY_VERSION-alpine AS base

WORKDIR /rails

RUN apk add --no-cache curl jemalloc

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    PATH="/rails/bin:$PATH"

FROM base AS build

RUN apk add --no-cache build-base git yaml-dev

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

RUN bundle exec bootsnap precompile app/ lib/

FROM base

COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

RUN addgroup -g 1000 -S rails && \
    adduser -u 1000 -S -G rails -h /home/rails -s /bin/sh rails && \
    chown -R rails:rails /rails && \
    chmod +x /rails/bin/*
USER 1000:1000

WORKDIR /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
