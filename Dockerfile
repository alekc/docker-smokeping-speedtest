FROM linuxserver/smokeping:2.9.0
ENV SMOKEPING_SPEEDTEST_DIR=/opt/smokeping-speedtest/
ENV SMOKEPING_PROBES_DIR=/usr/share/smokeping/Smokeping/probes/

COPY speedtest.Probe speedtest.Target /tmp/
RUN apk update \
    && apk add --no-cache --virtual .setupdeps git curl tar \
	&& apk add --no-cache speedtest-cli gcompat \
    && curl -L https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz | tar xz -C /usr/bin speedtest \
    && speedtest --accept-license --accept-gdpr --servers \
    && git clone https://github.com/mad-ady/smokeping-speedtest.git ${SMOKEPING_SPEEDTEST_DIR} \
    && cp ${SMOKEPING_SPEEDTEST_DIR}*.pm ${SMOKEPING_PROBES_DIR} \
    && cat /tmp/speedtest.Probe >> /defaults/smoke-conf/Probes \
    && cat /tmp/speedtest.Target >> /defaults/smoke-conf/Targets \
    && apk del .setupdeps \
    # && sed -i -e 's/\(range = 10h\)$/\1\nmax_rtt = 1000000000/' /defaults/smoke-conf/Presentation
	&& echo "Speedtest installed"
