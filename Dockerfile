# Variables declared before stages can be re-used; they will need to be
# redeclared explicitly, but the value only needs to be specified once.
ARG KOBWEB_APP_ROOT="site"

# Stage 1: Download the files needed to drive our site (from GitHub, where they were built)
FROM alpine:latest AS download

# Minimum deps needed to fetch and process responses / files
RUN apk add --no-cache curl jq unzip

ARG REPO_OWNER="bitspittle"
ARG REPO_NAME="kobweb-todo-on-render"
# The following is the name used in the GitHub workflow
ARG ARTIFACT_NAME="kobweb-folder"
ARG KOBWEB_APP_ROOT

# Render automatically injects this value during Docker builds. We will use it to ensure we download the right artifact.
ARG RENDER_GIT_COMMIT

# We will search for the artifact associated with our specific git commit. If for some reason the API says it can't find
# it, we'll try a few more times with exponential backoff, as maybe things are still propagating through GitHub's
# system. In practice, we expect to find the artifact on the first search.
RUN --mount=type=secret,id=GH_TOKEN,target=/etc/secrets/GH_TOKEN \
    set -e; \
    echo "==> [1/4] Starting artifact download process..."; \
    echo "    Target Commit: ${RENDER_GIT_COMMIT}"; \
    if [ -f /etc/secrets/GH_TOKEN ]; then \
      GH_TOKEN=$(cat /etc/secrets/GH_TOKEN); \
    fi; \
    if [ -z "$GH_TOKEN" ]; then \
      echo "==> Missing GH_TOKEN secret file." && exit 1; \
    fi; \
    \
    ARTIFACTS_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/artifacts?name=${ARTIFACT_NAME}"; \
    ARTIFACT_ID=""; \
    MAX_ATTEMPTS=5; \
    DELAY=2; \
    \
    echo "==> [2/4] Searching GitHub API for matching artifact (with retry/backoff)..."; \
    for attempt in $(seq 1 $MAX_ATTEMPTS); do \
      echo "    Attempt ${attempt}/${MAX_ATTEMPTS}..."; \
      RESPONSE=$(curl -sS -f -H "Authorization: Bearer $GH_TOKEN" "$ARTIFACTS_URL" || true); \
      \
      if [ -n "$RESPONSE" ]; then \
        ARTIFACT_ID=$(echo "$RESPONSE" | jq -r --arg SHA "$RENDER_GIT_COMMIT" \
          '(.artifacts // []) | map(select(.workflow_run.head_sha == $SHA)) | sort_by(.created_at) | last | .id // empty'); \
      fi; \
      \
      if [ -n "$ARTIFACT_ID" ]; then \
        echo "==> Match found! Artifact ID: ${ARTIFACT_ID}"; \
        break; \
      fi; \
      \
      if [ $attempt -lt $MAX_ATTEMPTS ]; then \
        echo "    Artifact for commit ${RENDER_GIT_COMMIT} not found yet. Retrying in ${DELAY}s..."; \
        sleep $DELAY; \
        DELAY=$((DELAY * 2)); \
      fi; \
    done; \
    \
    if [ -z "$ARTIFACT_ID" ]; then \
      echo "==> Failed to find artifact '${ARTIFACT_NAME}' for commit ${RENDER_GIT_COMMIT} after ${MAX_ATTEMPTS} attempts." && exit 1; \
    fi; \
    \
    ARTIFACT_URL="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/artifacts/${ARTIFACT_ID}/zip"; \
    echo "==> [3/4] Downloading zip file from ${ARTIFACT_URL} ..."; \
    curl -sS -f -L \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -o ${ARTIFACT_NAME}.zip \
      "$ARTIFACT_URL"; \
    \
    echo "==> [4/4] Extracting artifact to target directory..."; \
    mkdir -p /project/${KOBWEB_APP_ROOT}/.kobweb; \
    unzip -q ${ARTIFACT_NAME}.zip -d /project/${KOBWEB_APP_ROOT}/.kobweb; \
    echo "==> Download step completed successfully!"

#-----------------------------------------------------------------------------
# Create the final stage, which contains the minimum amout of stuff to run the
# Kobweb server. Use the latest JRE image available to us at this time.
FROM eclipse-temurin:21-jre AS run

ARG KOBWEB_APP_ROOT

WORKDIR /project/${KOBWEB_APP_ROOT}

COPY --from=download /project/${KOBWEB_APP_ROOT}/.kobweb .kobweb

# Because many free tiers only give you 512M of RAM, let's limit the server's
# memory usage to that. You can remove this ENV line if your server isn't so
# restricted. That said, 512M should be plenty for most (all?) sites.
ENV JAVA_TOOL_OPTIONS="-Xmx512m"

ENTRYPOINT ["/bin/sh", ".kobweb/server/start.sh"]
