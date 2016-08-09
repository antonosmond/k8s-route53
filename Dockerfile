FROM java:8

ENV K8S_VERSION 1.3.2

COPY run.sh .

RUN apt-get update && apt-get -y upgrade && \
    apt-get install -y jq && \
    curl https://bootstrap.pypa.io/get-pip.py | python2.7 && \
    pip install awscli && \
    curl "https://storage.googleapis.com/kubernetes-release/release/v${K8S_VERSION}/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    chmod +x run.sh

CMD ["/bin/bash", "run.sh"]
