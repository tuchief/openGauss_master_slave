FROM server.aiknown.cn:31003/base/openeuler:20.03-lts

EXPOSE 8080 5432 8008

WORKDIR /opt/software
COPY ./image /tmp/

RUN yum install -y --nogpgcheck tar iproute net-tools numactl numactl-libs
RUN yum clean all
RUN groupadd -r dbgrp && useradd -g dbgrp -G root omm && \
    mkdir -p /opt/software/openGauss && \
    tar -jxf /tmp/openGauss-*-openEuler-64bit.tar.bz2 -C /opt/software/openGauss && \
    rm -f /tmp/openGauss-*-openEuler-64bit.tar.bz2 && \
    mv /tmp/app.sh /opt/software/app.sh && \
    mv /tmp/entrypoint.sh /opt/software/entrypoint.sh && \
    mv /tmp/etcd.conf.sample /opt/software/etcd.conf.sample && \
    mv /tmp/patroni.yaml.sample /opt/software/patroni.yaml.sample 

# 解决patroni找不到gs_isready问题
RUN mv /tmp/gs_isready /opt/software/openGauss/bin/gs_isready && \
    mv /tmp/libreadline.so.6.2 /usr/lib64/libreadline.so.6.2 && \
    ln -sf /usr/lib64/libreadline.so.6.2 /usr/lib64/libreadline.so.6 && \
    chmod 777 /usr/lib64/libreadline.so.6

RUN mv /tmp/patroni_openGauss /opt/software/patroni_openGauss

ADD ./image/openGauss-*-openEuler-64bit-Libpq.tar.gz /opt/software/openGauss
RUN rm -Rf /tmp/openGauss-*-openEuler-64bit-Libpq.tar.gz

RUN tar -xzvf /tmp/etcd-*-linux-amd64.tar.gz -C /tmp/ && \
    rm -rf /tmp/etcd-*-linux-amd64.tar.gz && \
    cd /tmp/etcd-*-linux-amd64 && cp ./etcd* /usr/bin && \
    rm -rf /tmp/etcd-*-linux-amd64

RUN chown omm:dbgrp -R /opt/software
#    echo "omm" | sudo passwd omm --stdin  &>/dev/null && \
#    echo "root" | sudo passwd root --stdin  &>/dev/null && \
RUN chown omm:dbgrp -R /tmp/*
RUN chmod -R 700 /tmp/*
RUN chmod -R 700 /opt/software
RUN chmod +x /opt/software/openGauss/simpleInstall/install.sh
RUN chmod +x /opt/software/app.sh
RUN chmod +x /opt/software/entrypoint.sh

# 临时解决 host: command not found
RUN mv /tmp/host /usr/bin/host && \
    mv /tmp/libdns.so.1102.1.2 /usr/lib64/libdns.so.1102.1.2 && \
    ln -sf /usr/lib64/libdns.so.1102.1.2 /usr/lib64/libdns.so.1102 && \
    mv /tmp/liblwres.so.160.0.2 /usr/lib64/liblwres.so.160.0.2 && \
    ln -sf /usr/lib64/liblwres.so.160.0.2 /usr/lib64/liblwres.so.160 && \
    mv /tmp/libbind9.so.160.0.8 /usr/lib64/libbind9.so.160.0.8 && \
    ln -sf /usr/lib64/libbind9.so.160.0.8 /usr/lib64/libbind9.so.160 && \
    mv /tmp/libisccfg.so.160.2.1 /usr/lib64/libisccfg.so.160.2.1 && \
    ln -sf /usr/lib64/libisccfg.so.160.2.1 /usr/lib64/libisccfg.so.160 && \
    mv /tmp/libisc.so.169.0.3 /usr/lib64/libisc.so.169.0.3 && \
    ln -sf /usr/lib64/libisc.so.169.0.3 /usr/lib64/libisc.so.169 && \
    mv /tmp/libcrypto.so.1.0.2k /usr/lib64/libcrypto.so.1.0.2k && \
    ln -sf /usr/lib64/libcrypto.so.1.0.2k /usr/lib64/libcrypto.so.10 && \
    mv /tmp/libidn.so.11.6.11 /usr/lib64/libidn.so.11.6.11 && \
    ln -sf /usr/lib64/libidn.so.11.6.11 /usr/lib64/libidn.so.11 && \
    mv /tmp/libGeoIP.so.1.5.0 /usr/lib64/libGeoIP.so.1.5.0 && \
    ln -sf /usr/lib64/libGeoIP.so.1.5.0 /usr/lib64/libGeoIP.so.1 

RUN chmod 777 /usr/lib64/libdns.so.1102 /usr/lib64/liblwres.so.160 /usr/lib64/libisccfg.so.160 /usr/lib64/libisc.so.169\
    /usr/lib64/libcrypto.so.10 /usr/lib64/libidn.so.11 /usr/lib64/libGeoIP.so.1 /usr/lib64/libbind9.so.160

# 临时解决 [Errno 13] Permission denied: '/usr/local/python3.7/lib/python3.7/site-packages/
# RUN chown omm:dbgrp -R /usr/local/lib/python3.7/site-packages/

USER omm

ENV SOFT_HOME=/opt/software
ENV GAUSSHOME=$SOFT_HOME/openGauss
ENV PATH=$GAUSSHOME/bin:$PATH:/usr/local/python3.7/bin:/home/omm/venv/bin
ENV LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:/usr/lib
ENV LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH
ENV GS_CLUSTER_NAME=dbCluster
ENV ulimit -n 1000000

RUN tar -xzvf /tmp/openGauss-*-openEuler-x86_64-Python.tar.gz -C $GAUSSHOME

# 切换到 root，执行拷贝和授权
USER root
RUN chmod -R 755 $GAUSSHOME/psycopg2 && \
    chown -R root:root $GAUSSHOME/psycopg2 && \
    mv $GAUSSHOME/psycopg2 /usr/lib/python3.7/site-packages/
RUN rm -Rf /tmp/*

# 安装 pip for python3.7
RUN curl -sS https://mirrors.aliyun.com/pypi/get-pip.py -o get-pip.py && \
    /usr/bin/python3.7 get-pip.py && \
    rm -f get-pip.py \

USER omm
RUN /usr/bin/python3.7 -m pip install --upgrade pip --user && \
    pip install wheel --user && \
    cd /opt/software/patroni_openGauss && \
    pip install -r requirements.txt --user && \
    python setup.py build && python setup.py install --user && \
    rm -rf /opt/software/patroni_openGauss
RUN mkdir -p /opt/software/openGauss/data && \
    mkdir -p /opt/software/openGauss/logs

USER root
RUN yum clean all 
RUN mkdir -p /docker-entrypoint-initdb.d
ENTRYPOINT [ "/opt/software/entrypoint.sh" ]
CMD ["/bin/bash"]
