#-----------------------------------------------------------------------------
# Variables are shared across multiple stages (they need to be explicitly
# opted # into each stage by being declaring there too, but their values need
# only be # specified once).
ARG KOBWEB_APP_ROOT="site"

FROM eclipse-temurin:21-jdk AS java

#-----------------------------------------------------------------------------
# Create an intermediate stage which builds and exports our site. In the
# final stage, we'll only extract what we need from this stage, saving a lot
# of space.
FROM java AS export

ARG KOBWEB_APP_ROOT

# Copy the project code to an arbitrary subdir so we can install stuff in the
# Docker container root without worrying about clobbering project files.
COPY . /project

# Update and install required OS packages to continue
# Note: Node install instructions from: https://github.com/nodesource/distributions#installation-instructions
# Note: Playwright is a system for running browsers, and here we use it to
# install Chromium.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    unzip \
    wget \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/* \
    && npm init -y && npx playwright install --with-deps chromium

# Fetch and extract Kobweb CLI
RUN KOBWEB_CLI_VERSION=$(curl -sSL https://raw.githubusercontent.com/varabyte/data/refs/heads/main/kobweb/cli-version.txt | xargs) \
    && wget https://github.com/varabyte/kobweb-cli/releases/download/v${KOBWEB_CLI_VERSION}/kobweb-${KOBWEB_CLI_VERSION}.zip \
    && unzip kobweb-${KOBWEB_CLI_VERSION}.zip -d /opt \
    && rm kobweb-${KOBWEB_CLI_VERSION}.zip \
    && ln -s /opt/kobweb-${KOBWEB_CLI_VERSION} /opt/kobweb-cli

ENV PATH="/opt/kobweb-cli/bin:${PATH}"

WORKDIR /project/${KOBWEB_APP_ROOT}

# Decrease Gradle memory usage to avoid OOM situations in tight environments
# (many free Cloud tiers only give you 512M of RAM). The following amount
# should enough to build and export our site. If you ever get an OOM error,
# consider bumping the memory value up further.
# We also ask the Kotlin compiler to run inside Gradle instead of using its
# own daemon.
# Finally, serial GC is slower but apparently lowers the memory footprint
# of the build.
RUN mkdir -p ~/.gradle && echo "\
    org.gradle.daemon=false\n\
    org.gradle.jvmargs=-Xmx325m -XX:+UseSerialGC\n\
    kotlin.compiler.execution.strategy=in-process\n\
" > ~/.gradle/gradle.properties

RUN kobweb export --notty

#-----------------------------------------------------------------------------
# Create the final stage, which contains the minimum amout of stuff to run the
# Kobweb server.
FROM java AS run

ARG KOBWEB_APP_ROOT

WORKDIR /project/${KOBWEB_APP_ROOT}

COPY --from=export /project/${KOBWEB_APP_ROOT}/.kobweb .kobweb

# Because many free tiers only give you 512M of RAM, let's limit the server's
# memory usage to that. You can remove this ENV line if your server isn't so
# restricted. That said, 512M should be plenty for most (all?) sites.
ENV JAVA_TOOL_OPTIONS="-Xmx512m"

ENTRYPOINT ["/bin/sh", ".kobweb/server/start.sh"]
