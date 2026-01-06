FROM ruby:3.3-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git && \
    rm -rf /var/lib/apt/lists/*

COPY ruby/Gemfile ruby/Gemfile.lock /app/
RUN bundle config set path '/app/vendor/bundle' && bundle install

COPY shared /app/shared
COPY ruby /app/ruby

EXPOSE 8002

WORKDIR /app/ruby

CMD ["bundle", "exec", "ruby", "index.rb"]
