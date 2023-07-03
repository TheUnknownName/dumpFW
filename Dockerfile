FROM ubuntu:jammy
LABEL maintainer="TUNBudi06 <anjaytun2006@gmail.com>"
ENV DEBIAN_FRONTEND noninteractive

WORKDIR /tmp

RUN apt-get -yqq update \
    && apt-get -yqq upgrade \
    && apt-get install -y git sudo neofetch unzip apt-utils curl wget 

RUN wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip \
    && unzip platform-tools-latest-linux.zip -d /tmp/ \
    && export PATH="/tmp/platform-tools:$PATH"
    
RUN cd /tmp \
  && git clone https://github.com/akhilnarang/scripts \
  && cd scripts \
  && bash setup/android_build_env.sh

RUN mkdir -p /tmp/bin 

RUN curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/bin/repo \
  && chmod a+x /tmp/bin/repo && export PATH="/tmp/bin:$PATH"
  
VOLUME ["/tmp/bin", "/tmp/rom"]
ENTRYPOINT ["/bin/bash"]
