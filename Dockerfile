FROM lasplang/erlang:19.3

MAINTAINER Christopher S. Meiklejohn <christopher.meiklejohn@gmail.com>

RUN cd /tmp && \
    apt-get update && \
    apt-get -y install wget build-essential make gcc ruby-dev git expect gnuplot tmux

RUN cd /opt && \
    git clone https://github.com/lasp-lang/unir.git && \
    cd unir && \
    make && \
    make release

CMD cd /opt/unir && \
    ./rebar3 proper -m prop_unir -p prop_sequential