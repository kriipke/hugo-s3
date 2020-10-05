FROM ruby:alpine3.12

LABEL description="serve / build Hugo site"
# config
ENV HUGO_VERSION=0.75.1
ENV HUGO_TYPE=_extended

ENV URL=https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo${HUGO_TYPE}_${HUGO_VERSION}_Linux-64bit.tar.gz
RUN wget -O - ${URL} | tar -xz -C /usr/sbin hugo \
    && apk add --no-cache ca-certificates git asciidoctor libc6-compat libstdc++ \
    && cd /tmp \
    && wget -O "awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm ./awscliv2.zip \
    && gem install asciidoctor-rouge rouge asciidoctor-interdoc-reftext asciidoctor-diagram asciidoctor-html5s

COPY ./run.sh /run.sh
VOLUME /src
VOLUME /output
VOLUME /root/.aws

WORKDIR /src
ENTRYPOINT ["/run.sh"]

EXPOSE 1313
