FROM mcr.microsoft.com/devcontainers/java:1-17-bookworm

ARG ANDROID_COMMAND_LINE_TOOLS_VERSION=11076708

ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    PATH=/opt/android-sdk/cmdline-tools/latest/bin:/opt/android-sdk/platform-tools:${PATH}

RUN rm -f /etc/apt/sources.list.d/yarn.list \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl \
        make \
        shellcheck \
        unzip \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p "${ANDROID_HOME}/cmdline-tools" \
    && curl --fail --location --retry 3 \
        "https://dl.google.com/android/repository/commandlinetools-linux-${ANDROID_COMMAND_LINE_TOOLS_VERSION}_latest.zip" \
        --output /tmp/android-tools.zip \
    && unzip -q /tmp/android-tools.zip -d /tmp/android-tools \
    && mv /tmp/android-tools/cmdline-tools "${ANDROID_HOME}/cmdline-tools/latest" \
    && rm -rf /tmp/android-tools /tmp/android-tools.zip \
    && yes | sdkmanager --licenses >/dev/null \
    && sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0" \
    && ln -s "${ANDROID_HOME}/cmdline-tools/latest/bin/sdkmanager" /usr/local/bin/sdkmanager \
    && ln -s "${ANDROID_HOME}/cmdline-tools/latest/bin/avdmanager" /usr/local/bin/avdmanager \
    && ln -s "${ANDROID_HOME}/platform-tools/adb" /usr/local/bin/adb \
    && chown -R vscode:vscode "${ANDROID_HOME}"
