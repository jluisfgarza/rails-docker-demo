# I: Runtime Stage: ============================================================
# This is the stage where we build the runtime base image, which is used as the
# common ancestor by the rest of the stages, and contains the minimal runtime
# dependencies required for the application to run:

# 1: Start off from Ruby 2.5.1 on Alpine Linux 3.7:
FROM ruby:2.5.1-alpine3.7 AS runtime

# 2: We'll set '/usr/src' path as the working directory:
WORKDIR /usr/src

# 3: We'll set the working dir as HOME and add the app's binaries path to $PATH:
ENV HOME=/usr/src PATH=/usr/src/bin:$PATH

# 4: Install the common runtime dependencies:
RUN apk add --no-cache ca-certificates less libpq nodejs openssl tzdata

RUN apk add --update bash && rm -rf /var/cache/apk/*

# II: Development Stage: =======================================================
# In this stage we'll build the image used for development, including compilers,
# and development libraries. This is also a first step for building a releasable
# Docker image:

# 1: Start off from the "runtime" stage:
FROM runtime AS development

# 2: Install the development dependency packages with alpine package manager:
RUN apk add --no-cache \
    build-base \
    chromium \
    chromium-chromedriver \
    git \
    postgresql-dev \
    yarn

# 3: Install the 'check-dependencies' node package:
RUN npm install -g check-dependencies

# 4: Copy the project's Gemfile + lock:
ADD Gemfile* /usr/src/

# 5: Install the current project gems - they can be safely changed later during
# development via `bundle install` or `bundle update`:
RUN bundle install --jobs=4 --retry=3

# 6: Set the default command:
CMD ["rails", "server", "-b", "0.0.0.0"]

# III: Builder stage: ==========================================================
# In this stage we'll compile assets coming from the project's source, do some
# tests and cleanup. If the CI/CD that builds this image allows it, we should
# also run the app test suites here:

# 1: Start off from the development stage image:
FROM development AS builder

# 2: Copy the rest of the application code
ADD . /usr/src

# 3: Precompile assets:
RUN export DATABASE_URL=postgres://postgres@example.com:5432/fakedb \
    SECRET_KEY_BASE=10167c7f7654ed02b3557b05b88ece \
    DB_HOST=db \
    DB_USER=user \
    DB_PASSWORD=secret \ 
    RAILS_ENV=production && \
    rails assets:precompile && \
    rails secret > /dev/null

# 4: Remove installed gems that belong to the development & test groups - we'll
# copy the remaining system gems into the deployable image on the next stage:
RUN bundle config without development:test && bundle clean && rm -rf tmp/*

# IV: Deployable stage: ========================================================
# In this stage, we build the final, deployable Docker image, which will be
# smaller than the images generated on previous stages:

# 1: Start off from the runtime stage image:
FROM runtime AS deployable

# 2: Copy the remaining installed gems from the "builder" stage:
COPY --from=builder /usr/local/bundle /usr/local/bundle

# 3: Copy from app code from the "builder" stage, which at this point should
# have the assets from the asset pipeline already compiled:
COPY --from=builder /usr/src /usr/src

# 3: Set the RAILS/RACK_ENV and PORT default values:
ENV RAILS_ENV=production RACK_ENV=production PORT=3000

# 4: Generate the temporary directories in case they don't already exist:
RUN mkdir -p /usr/src/tmp/cache && \
    mkdir -p /usr/src/tmp/pids && \
    mkdir -p /usr/src/tmp/sockets && \
    chown -R nobody /usr/src

# 5: Set the container user to 'nobody':
USER nobody

# 6: Set the default command:
CMD [ "puma" ]