FROM varnish:7.6.1

WORKDIR /app

ARG VERSION=001

ARG BACKEND_HOST
ARG BACKEND_PORT

COPY ./proxy.vcl.in /tmp/proxy.vcl.in

RUN sed "s/{{HOST}}/$BACKEND_HOST/g; s/{{PORT}}/$BACKEND_PORT/g" < /tmp/proxy.vcl.in > /app/default.vcl

ENTRYPOINT ["/usr/sbin/varnishd", "-F", "-s", "malloc,256m", "-p", "feature=+http2" , "-p", "workspace_client=32k", "-p", "thread_pool_max=5000", "-f", "/app/default.vcl"]

