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
    if [ -f /etc/secrets/GH_TOKEN ]; then \
      GH_TOKEN=$(cat /etc/secrets/GH_TOKEN); \
    fi; \
    if [ -z "$GH_TOKEN" ]; then \
      echo "==> GH_TOKEN secret file is missing." && exit 1; \
    fi; \
    RESPONSE=$(curl -sS -f -H "Authorization: Bearer $GH_TOKEN" \
      "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/artifacts?name=${ARTIFACT_NAME}"); \
    ARTIFACT_ID=$(echo "$RESPONSE" | jq -r '.artifacts | sort_by(.created_at) | reverse | .[0].id // empty'); \
    if [ -z "$ARTIFACT_ID" ]; then \
      echo "==> Could not find artifact named ${ARTIFACT_NAME} in ${REPO_OWNER}/${REPO_NAME}" && exit 1; \
    fi; \
    curl -sS -f -L \
      -H "Authorization: Bearer $GH_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -o ${ARTIFACT_NAME}.zip \
      "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/artifacts/${ARTIFACT_ID}/zip"; \
    mkdir -p /project/${KOBWEB_APP_ROOT}/.kobweb; \
    unzip -q ${ARTIFACT_NAME}.zip -d /project/${KOBWEB_APP_ROOT}/.kobweb

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
