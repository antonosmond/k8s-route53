FROM java:8

COPY run.sh .

RUN apt-get update && apt-get -y upgrade && \
    apt-get install -y jq && \
    curl https://bootstrap.pypa.io/get-pip.py | python2.7 && \
    pip install awscli && \
    chmod +x run.sh

CMD ["/bin/bash", "run.sh"]
