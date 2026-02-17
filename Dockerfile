FROM linuxserver/smokeping:2.9.0
ENV SMOKEPING_PROBES_DIR=/usr/share/smokeping/Smokeping/probes/

COPY speedtest.Probe speedtest.Target /tmp/
COPY speedtest.pm speedtestcli.pm ${SMOKEPING_PROBES_DIR}
RUN apk update \
    && apk add --no-cache --virtual .setupdeps curl tar \
	&& apk add --no-cache speedtest-cli gcompat \
    && curl -L https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz | tar xz -C /usr/bin speedtest \
    && speedtest --accept-license --accept-gdpr --servers \
    && cat /tmp/speedtest.Probe >> /defaults/smoke-conf/Probes \
    && cat /tmp/speedtest.Target >> /defaults/smoke-conf/Targets \
    && apk del .setupdeps \
    # && sed -i -e 's/\(range = 10h\)$/\1\nmax_rtt = 1000000000/' /defaults/smoke-conf/Presentation
	&& echo "Speedtest installed"
