FROM openjdk:8-jdk
MAINTAINER Buttetsu Batou <doubledense@gmail.com>

RUN apt-get update
RUN apt-get install apt-transport-https

RUN apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
RUN echo "deb https://apt.dockerproject.org/repo debian-jessie main" > /etc/apt/sources.list.d/docker.list

RUN apt-get install -y git curl zip nfs-common sudo ca-certificates ccache cmake python-dev libffi-dev libyaml-dev libssl-dev python-setuptools bc jq && rm -rf /var/lib/apt/lists/*

# workaround from https://github.com/ansible/ansible/issues/17578
RUN easy_install pip

# adding Ansible
RUN pip install --upgrade cffi
RUN pip install paramiko PyYAML Jinja2 httplib2 six
RUN git clone git://github.com/ansible/ansible.git --recursive
WORKDIR /ansible
# using my fork that merges patbaker82's MAC address support and mihai-satmarean's bios boot options support
# see https://github.com/ansible/ansible-modules-core/pull/3643 , https://github.com/ansible/ansible-modules-core/issues/3615 and https://github.com/ansible/ansible-modules-core/pull/3914/commits/4fc8f6a52356403ba9eb74c05a7c10450eea580b
RUN sed -i.bak 's|https://github.com/ansible/ansible-modules-core|https://github.com/doubledensity/ansible-modules-core.git|g' .gitmodules
RUN git submodule sync --recursive
RUN git submodule update --init --recursive
RUN git --git-dir=/ansible/lib/ansible/modules/core/.git --work-tree=/ansible/lib/ansible/modules/core config user.email "doubledense@gmail.com"
RUN git --git-dir=/ansible/lib/ansible/modules/core/.git --work-tree=/ansible/lib/ansible/modules/core config user.name "Buttetsu Batou"
RUN git --git-dir=/ansible/lib/ansible/modules/core/.git --work-tree=/ansible/lib/ansible/modules/core pull origin devel
RUN bash -c "source ./hacking/env-setup"
RUN ln -s /ansible/bin/ansible-playbook /usr/bin/ansible-playbook

# pysphere for Ansible VMware support
RUN apt-get update
RUN pip install pysphere

# install AWS CLI
RUN pip install awscli

# install fleet for managing CoreOS clusters
RUN wget https://github.com/coreos/fleet/releases/download/v0.11.8/fleet-v0.11.8-linux-amd64.tar.gz && tar zxvf fleet-v0.11.8-linux-amd64.tar.gz
RUN cp fleet-v0.11.8-linux-amd64/fleetctl /usr/local/bin
RUN chmod +x /usr/local/bin/fleetctl

# adding Docker 1.10.3 specifically to interoperate with CoreOS Stable 1122.3
WORKDIR /
ADD https://get.docker.com/builds/Linux/x86_64/docker-1.10.3.tgz /
RUN tar zxvf docker-1.10.3.tgz

ENV JENKINS_HOME /var/jenkins_home
ENV JENKINS_SLAVE_AGENT_PORT 50000

ARG user=jenkins
ARG group=jenkins
ARG uid=501
ARG gid=80

# Jenkins is run with user `jenkins`, uid = 1000
# If you bind mount a volume from the host or a data container, 
# ensure you use the same uid
RUN groupadd -g ${gid} ${group} \
    && useradd -d "$JENKINS_HOME" -u ${uid} -g ${gid} -m -s /bin/bash ${user}

# Jenkins home directory is a volume, so configuration and build history 
# can be persisted and survive image upgrades
# Disabling volume to use NFS mount instead
#VOLUME /var/jenkins_home

# Add jenkins user to sudoers
RUN echo "${user} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# `/usr/share/jenkins/ref/` contains all reference configuration we want 
# to set on a fresh new installation. Use it to bundle additional plugins 
# or config file with your custom jenkins Docker image.
RUN mkdir -p /usr/share/jenkins/ref/init.groovy.d

ENV TINI_VERSION 0.9.0
ENV TINI_SHA fa23d1e20732501c3bb8eeeca423c89ac80ed452

# Use tini as subreaper in Docker container to adopt zombie processes 
RUN curl -fsSL https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static -o /bin/tini && chmod +x /bin/tini \
  && echo "$TINI_SHA  /bin/tini" | sha1sum -c -

COPY init.groovy /usr/share/jenkins/ref/init.groovy.d/tcp-slave-agent-port.groovy

# jenkins version being bundled in this docker image
ARG JENKINS_VERSION
ENV JENKINS_VERSION ${JENKINS_VERSION:-2.19.1}

# jenkins.war checksum, download will be validated using it
ARG JENKINS_SHA=dc28b91e553c1cd42cc30bd75d0f651671e6de0b

# Can be used to customize where jenkins.war get downloaded from
ARG JENKINS_URL=https://repo.jenkins-ci.org/public/org/jenkins-ci/main/jenkins-war/${JENKINS_VERSION}/jenkins-war-${JENKINS_VERSION}.war

# could use ADD but this one does not check Last-Modified header neither does it allow to control checksum 
# see https://github.com/docker/docker/issues/8331
RUN curl -fsSL ${JENKINS_URL} -o /usr/share/jenkins/jenkins.war \
  && echo "${JENKINS_SHA}  /usr/share/jenkins/jenkins.war" | sha1sum -c -

ENV JENKINS_UC https://updates.jenkins.io
RUN chown -R ${user} "$JENKINS_HOME" /usr/share/jenkins/ref

# for main web interface:
EXPOSE 8080

# will be used by attached slave agents:
EXPOSE 50000

ENV COPY_REFERENCE_FILE_LOG $JENKINS_HOME/copy_reference_file.log

USER ${user}

COPY jenkins-support /usr/local/bin/jenkins-support
COPY jenkins.sh /usr/local/bin/jenkins.sh
ENTRYPOINT ["/bin/tini", "--", "/usr/local/bin/jenkins.sh"]

# from a derived Dockerfile, can use `RUN plugins.sh active.txt` to setup /usr/share/jenkins/ref/plugins from a support bundle
COPY plugins.sh /usr/local/bin/plugins.sh
COPY install-plugins.sh /usr/local/bin/install-plugins.sh
