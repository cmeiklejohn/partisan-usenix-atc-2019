FROM erlang:20.3

MAINTAINER Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>

RUN cd /tmp && \
    apt-get update && \
    apt-get -y install wget build-essential make gcc ruby-dev git expect gnuplot tmux && \
    gem install gist

CMD echo "${GIST_TOKEN}" > /root/.gist && \
    echo "kube running for ${HOSTNAME}" | gist && \
    cd /opt && \
    git clone https://github.com/lasp-lang/unir.git && \
    cd unir && \
    make | tee output-make.txt && \
    make release | tee output-release.txt && \
    make proper | tee output-proper.txt; exit 0 && \
    gist -d "${HOSTNAME}" output-*.txt _build/test/*-counterexamples.consult