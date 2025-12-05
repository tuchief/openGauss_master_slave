FROM server.aiknown.cn:31003/base/openeuler:20.03-lts_arm

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
RUN mv /tmp/gs_isready /opt/software/openGauss/bin/gs_isready 
RUN mv /tmp/libreadline.so.7 /usr/lib64/libreadline.so.7
RUN mv /tmp/libreadline.so.7.0 /usr/lib64/libreadline.so.7.0
RUN mv /tmp/libaio.so.1 /usr/lib64/libaio.so.1
RUN mv /tmp/libaio.so.1.0.1 /usr/lib64/libaio.so.1.0.1
RUN mv /tmp/libpq.so.private13-5 /usr/lib64/libpq.so.private13-5
RUN mv /tmp/libpq.so.private13-5.13 /usr/lib64/libpq.so.private13-5.13
RUN mv /tmp/libldap.so.2 /usr/lib64/libldap.so.2
RUN mv /tmp/libldap.so.2.0.200 /usr/lib64/libldap.so.2.0.200
RUN mv /tmp/liblber.so.2 /usr/lib64/liblber.so.2
RUN mv /tmp/liblber.so.2.0.200 /usr/lib64/liblber.so.2.0.200
RUN mv /tmp/libc.so.6 /usr/lib64/libc.so.6
RUN chmod 777 /usr/lib64/libreadline.so.7


RUN mv /tmp/patroni_openGauss /opt/software/patroni_openGauss

ADD ./image/openGauss-*-openEuler-64bit-Libpq.tar.gz /opt/software/openGauss
RUN rm -Rf /tmp/openGauss-*-openEuler-64bit-Libpq.tar.gz

RUN tar -xzvf /tmp/etcd-*-linux-arm64.tar.gz -C /tmp/ && \
    rm -rf /tmp/etcd-*-linux-arm64.tar.gz && \
    cd /tmp/etcd-*-linux-arm64 && cp ./etcd* /usr/bin && \
    rm -rf /tmp/etcd-*-linux-arm64

RUN chown omm:dbgrp -R /opt/software
#RUN echo "omm" | passwd omm --stdin  &>/dev/null
#RUN echo "root" | passwd root --stdin  &>/dev/null
RUN chown omm:dbgrp -R /tmp/*
RUN chmod -R 700 /tmp/*
RUN chmod -R 700 /opt/software
RUN chmod +x /opt/software/openGauss/simpleInstall/install.sh
RUN chmod +x /opt/software/app.sh
RUN chmod +x /opt/software/entrypoint.sh    

USER omm
ENV SOFT_HOME=/opt/software
ENV GAUSSHOME=$SOFT_HOME/openGauss
ENV PATH=$GAUSSHOME/bin:$PATH:/usr/local/python3.7/bin:/home/omm/venv/bin
ENV LD_LIBRARY_PATH=/usr/local/lib64:/usr/local/lib:/usr/lib
ENV LD_LIBRARY_PATH=$GAUSSHOME/lib:$LD_LIBRARY_PATH
ENV GS_CLUSTER_NAME=dbCluster
#ENV ulimit -n 1000000
# 设置 PGDATA
ENV PGDATA=/opt/software/openGauss/data/db
                   
RUN tar -xzvf /tmp/openGauss-*-openEuler-aarch64-Python.tar.gz -C $GAUSSHOME

# 切换到 root，执行拷贝和授权
USER root
RUN chmod -R 755 /opt/software/openGauss/psycopg2 && \
    chown -R root:root /opt/software/openGauss/psycopg2 && \
    mv /opt/software/openGauss/psycopg2 /usr/lib/python3.7/site-packages/

USER omm
ENV PATH=/home/omm/.local/bin:$PATH
# 安装 pip for python3.7
RUN  /usr/bin/python3.7 -m pip install /tmp/pip-20.3.4-py2.py3-none-any.whl --user

RUN pip install wheel --user -i https://mirrors.aliyun.com/pypi/simple/
RUN cd /opt/software/patroni_openGauss && \
    pip install -r requirements.txt --user -i https://mirrors.aliyun.com/pypi/simple/ && \
    python3 setup.py build && python3 setup.py install --user
RUN rm -rf /opt/software/patroni_openGauss

RUN mkdir -p /opt/software/openGauss/data
RUN mkdir -p /opt/software/openGauss/logs

USER root
# 创建软链接
RUN ln -s /opt/software/openGauss /usr/local/opengauss

#RUN yum clean all
RUN rm -Rf /tmp/*
RUN rm -rf /var/cache/yum /var/cache/dnf
RUN mkdir -p /docker-entrypoint-initdb.d
ENTRYPOINT [ "/opt/software/entrypoint.sh" ]
CMD ["/bin/bash"]
