FROM consul:1.4.4 as consul-source
FROM docker:18.06.1-ce as docker-source
FROM hashicorp/terraform:0.11.14 as terraform-0.11
FROM hashicorp/terraform:0.12.16 as terraform-0.12
FROM hashicorp/packer:1.4.4 as packer-source
FROM vault:1.2.3 as vault-source
FROM gcr.io/cloudsql-docker/gce-proxy:1.16 as cloudsqlproxy-source

FROM ubuntu:18.04

# common initial setup
RUN apt-get -q update && \
    DEBIAN_FRONTEND=noninteractive apt-get -q install -y \
                                   apt-transport-https \
                                   bind9-host \
                                   ca-certificates \
                                   curl \
                                   dnsutils \
                                   gettext-base \
                                   git \
                                   iputils-ping \
                                   jq \
                                   libssl-dev \
                                   openssh-client \
                                   python-paramiko \
                                   python-pip \
                                   python-pytest\
                                   python3-paramiko \
                                   python3-pip \
                                   python3-pytest \
                                   wget \
                                   zip \
                                   unzip \
                                   uuid-runtime

# install and setup all of the apt keys / repos in the apt subdir
# this way, a single apt-get update pulls in all of the external repos
ADD apt/* /tmp/apt/
RUN for i in /tmp/apt/*.key; do apt-key add $i; done && \
    cp /tmp/apt/*.list /etc/apt/sources.list.d && \
    rm -rf /tmp/apt && \
    apt-get update

# common python modules
RUN /usr/bin/pip --no-cache-dir install awscli awsrequests testinfra && \
    /usr/bin/pip3 --no-cache-dir install awscli awsrequests testinfra


# go config
ENV GOPATH=/go
RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" && chmod -R 777 "$GOPATH"
ENV GOROOT=/usr/local/go
ENV PATH $GOPATH/bin:$GOROOT/bin:$PATH

# updated golang
ENV go_ver=1.13.3
ENV go_sha256=0804bf02020dceaa8a7d7275ee79f7a142f1996bfd0c39216ccb405f93f994c0
RUN cd root && \
    wget https://dl.google.com/go/go${go_ver}.linux-amd64.tar.gz && \
    echo "${go_sha256} go${go_ver}.linux-amd64.tar.gz" > sha256sums && \
    (sha256sum -c sha256sums --strict) && \
    tar -C /usr/local -xvf go${go_ver}.linux-amd64.tar.gz && \
    rm go${go_ver}.linux-amd64.tar.gz && \
    go get -u golang.org/x/lint/golint

# aws-sudo
ADD aws-sudo/aws-sudo.sh /usr/local/bin/aws-sudo.sh

# google-sdk
RUN DEBIAN_FRONTEND=noninteractive apt-get -q install -y google-cloud-sdk \
                                                         kubectl && \
    gcloud config set core/disable_usage_reporting true && \
    gcloud config set component_manager/disable_update_check true

# gcr docker credential helper
ENV gcr_cred_helper_ver=1.4.3
ENV gcr_cred_helper_sha256=0630f744a5f42bf14e5986c959f32c5770a1f32d50ba055bd98353c7d18292d3
RUN curl -L -o /root/gcrhelper.tar.gz https://github.com/GoogleCloudPlatform/docker-credential-gcr/releases/download/v${gcr_cred_helper_ver}-static/docker-credential-gcr_linux_amd64-${gcr_cred_helper_ver}.tar.gz && \
    echo "${gcr_cred_helper_sha256} gcrhelper.tar.gz" > /root/sha256sums && \
    (cd /root; sha256sum -c sha256sums --strict) && \
    tar zxvf /root/gcrhelper.tar.gz -C /root && \
    install /root/docker-credential-gcr /usr/local/bin

# ecs-cli
RUN curl -o /usr/local/bin/ecs-cli https://s3.amazonaws.com/amazon-ecs-cli/ecs-cli-linux-amd64-latest && \
    echo "$(curl -s https://s3.amazonaws.com/amazon-ecs-cli/ecs-cli-linux-amd64-latest.md5) /usr/local/bin/ecs-cli" | md5sum -c - && \
    chmod +x /usr/local/bin/ecs-cli

# install helm
RUN mkdir tmp-helm && \
    cd tmp-helm && \
    curl -o "./helm-v3.0.2-linux-amd64.tar.gz" "https://get.helm.sh/helm-v3.0.2-linux-amd64.tar.gz" && \
    echo "c6b7aa7e4ffc66e8abb4be328f71d48c643cb8f398d95c74d075cfb348710e1d helm-v3.0.2-linux-amd64.tar.gz" > sha256sums && \
    sha256sum -c sha256sums --strict && \
    tar -zxvf helm-v3.0.2-linux-amd64.tar.gz && \
    mv linux-amd64/helm  /usr/local/bin/ && \
    rm -rf ../tmp-helm

# node 9.x
RUN echo "send-metrics = false" > /etc/npmrc && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs yarn && \
    npm install npm --global

# populate static binaries from source images
COPY --from=consul-source /bin/consul /usr/local/bin/consul
COPY --from=docker-source /usr/local/bin/docker /usr/local/bin/docker
COPY --from=packer-source /bin/packer /usr/local/bin/packer
COPY --from=vault-source /bin/vault /usr/local/bin/vault

# Terraform 0.11
COPY --from=terraform-0.11 /bin/terraform /usr/local/bin/terraform
RUN ln -s /usr/local/bin/terraform /usr/local/bin/terraform-0.11

# Terraform 0.12
COPY --from=terraform-0.12 /bin/terraform /usr/local/bin/terraform-0.12

# Cloud SQL proxy
COPY --from=cloudsqlproxy-source /cloud_sql_proxy /usr/local/bin/cloud_sql_proxy

# disable hashicorp phone-home
ENV CHECKPOINT_DISABLE=1

# cleanup
RUN rm -rf /root/* /tmp/* /google-cloud-sdk/.install/.backup
