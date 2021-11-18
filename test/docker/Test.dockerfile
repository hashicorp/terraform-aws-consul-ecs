# This Dockerfile includes the dependencies for unit and acceptance tests
# run in CircleCI.
FROM circleci/golang:1.17

# change the user to root so we can install stuff
USER root

ENV TERRAFORM_VERSION "1.0.10"

# base packages
RUN apt-get install -y \
    openssl \
    jq

# terraform
RUN curl -sSL https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip -o /tmp/tf.zip \
    && unzip /tmp/tf.zip  \
    && mv ./terraform /usr/local/bin/terraform \
    && rm -f /tmp/tf.zip \
    && terraform --version

# AWS CLI
RUN curl -sSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install --bin-dir /usr/local/bin \
    && rm awscliv2.zip \
    && rm -rf ./aws \
    && aws --version

# session-manager-plugin for 'aws ecs execute-command'
RUN curl -sSL https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb -o session-manager-plugin.deb \
    && sudo dpkg -i session-manager-plugin.deb  \
    && rm session-manager-plugin.deb

# ecs-cli
RUN curl -sSLo /usr/local/bin/ecs-cli https://amazon-ecs-cli.s3.amazonaws.com/ecs-cli-linux-amd64-latest \
    && chmod +x /usr/local/bin/ecs-cli \
    && ecs-cli --version

# change the user back to what circleci/golang image has
USER circleci
