FROM registry.access.redhat.com/ubi9/ubi:latest

RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    && dnf install -y --nodocs squid \
    && dnf clean all

COPY squid.conf /etc/squid/squid.conf

RUN mkdir -p /var/log/squid /var/spool/squid /var/run/squid \
    && chown -R squid:0 /var/log/squid /var/spool/squid /var/run/squid \
    && chmod -R g+rwX /var/log/squid /var/spool/squid /var/run/squid

EXPOSE 3128
USER squid

CMD ["squid", "-N", "-f", "/etc/squid/squid.conf"]
