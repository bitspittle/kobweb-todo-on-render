# Variables declared before stages can be re-used; they will need to be
# redeclared explicitly, but the value only needs to be specified once.
ARG KOBWEB_APP_ROOT="site"

# Stage 1: Download the site files (build by GitHub)
FROM alpine:latest AS download

# Minimum deps needed to fetch
RUN apk add --no-cache curl jq unzip

ARG REPO_OWNER="bitspittle"
ARG REPO_NAME="kobweb-todo-on-render"
# The following is the name used in the GitHub workflow
ARG ARTIFACT_NAME="kobweb-folder"
ARG KOBWEB_APP_ROOT

# There's no way to know exactly which export artifact is the one that triggered us, but just download the latest one.
RUN --mount=type=secret,id=GH_TOKEN,target=/etc/secrets/GH_TOKEN \
    set -e; \
    echo "==> [1/5] Starting site download process..."; \
    if [ -f /etc/secrets/GH_TOKEN ]; then \
      GH_TOKEN=$(cat /etc/secrets/GH_TOKEN); \
    fi; \
    if [ -z "$GH_TOKEN" ]; then \
      echo "==> Missing GH_TOKEN secret file or environment variable." && exit 1; \
    fi; \
    \
    API_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/artifacts?name=${ARTIFACT_NAME}"; \
    echo "==> [2/5] Querying GitHub API for artifact metadata..."; \
    echo "    URL: ${API_URL}"; \
    RESPONSE=$(curl -sS -f -H "Authorization: Bearer $GH_TOKEN" "$API_URL"); \
    \
    ARTIFACT_ID=$(echo "$RESPONSE" | jq -r '(.artifacts // []) | sort_by(.created_at) | last | .id // empty'); \
    if [ -z "$ARTIFACT_ID" ]; then \
      echo "==> Could not find artifact named '${ARTIFACT_NAME}' in ${REPO_OWNER}/${REPO_NAME}" && exit 1; \
    fi; \
    \
    DOWNLOAD_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/artifacts/${ARTIFACT_ID}/zip"; \
    echo "==> [3/5] Target artifact located successfully!"; \
    echo "    Artifact ID: ${ARTIFACT_ID}"; \
    echo "    Download URL: ${DOWNLOAD_URL}"; \
    \
    echo "==> [4/5] Downloading zip file..."; \
    curl -sS -f -L \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -o ${ARTIFACT_NAME}.zip \
      "$DOWNLOAD_URL"; \
    echo "    Download complete!"; \
    \
    echo "==> [5/5] Extracting artifact to target directory..."; \
    mkdir -p /project/${KOBWEB_APP_ROOT}/.kobweb; \
    unzip -q ${ARTIFACT_NAME}.zip -d /project/${KOBWEB_APP_ROOT}/.kobweb; \
    echo "==> Download step completed successfully!"

#-----------------------------------------------------------------------------
# Create the final stage, which contains the minimum amout of stuff to run the
# Kobweb server.
FROM eclipse-temurin:21-jre AS run

ARG KOBWEB_APP_ROOT

WORKDIR /project/${KOBWEB_APP_ROOT}

COPY --from=download /project/${KOBWEB_APP_ROOT}/.kobweb .kobweb

# Because many free tiers only give you 512M of RAM, let's limit the server's
# memory usage to that. You can remove this ENV line if your server isn't so
# restricted. That said, 512M should be plenty for most (all?) sites.
ENV JAVA_TOOL_OPTIONS="-Xmx512m"

ENTRYPOINT ["/bin/sh", ".kobweb/server/start.sh"]
