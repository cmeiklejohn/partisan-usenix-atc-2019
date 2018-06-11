FROM erlang:20.3

MAINTAINER Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>

RUN cd /tmp && \
    apt-get update && \
    apt-get -y install wget build-essential make gcc ruby-dev git expect gnuplot tmux && \
    gem install gist && \
    cd /opt && \
    git clone https://github.com/lasp-lang/unir.git && \
    cd unir && \
    make release

CMD echo "${GIST_TOKEN}" > /root/.gist && \
    echo "kube running for ${HOSTNAME}" | gist && \
    export LC_ALL=en_US.UTF-8 && \
    export LANG=en_US.UTF-8 && \
    cd /opt/unir && \
    git pull && \
    make && \
    (ulimit -n 65534; ./rebar3 proper -m prop_unir -p prop_sequential; exit 0) | tee output-proper.txt && \
    (make proper-logs; exit 0) | tee output-logs.txt && \
    chmod 755 bin/gist-results && \
    bin/gist-results
