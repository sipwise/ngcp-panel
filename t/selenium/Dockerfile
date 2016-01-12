# DOCKER_NAME=ngcp-panel-tests-selenium-jessie
FROM docker.mgm.sipwise.com/sipwise-jessie:latest

# Important! Update this no-op ENV variable when this Dockerfile
# is updated with the current date. It will force refresh of all
# of the base images and things like `apt-get update` won't be using
# old cached versions when the Dockerfile is built.
ENV REFRESHED_AT 2016-01-12

RUN apt-get update
RUN apt-get install --assume-yes \
	devscripts \
        fluxbox \
        git \
        iceweasel \
        libtap-formatter-junit-perl \
        lsof \
        net-tools \
        openjdk-7-jre-headless \
        vim-tiny \
        vnc4server \
        wget \
        xterm

RUN adduser --disabled-password --gecos=Selenium-User selenium

WORKDIR /home/selenium
RUN wget -O selenium-server-standalone-2.47.1.jar http://selenium-release.storage.googleapis.com/2.47/selenium-server-standalone-2.47.1.jar
RUN ln -s selenium-server-standalone-2.47.1.jar selenium-server-standalone.jar

WORKDIR /tmp/
COPY control /tmp/
RUN mk-build-deps /tmp/control
RUN dpkg --force-depends -i /tmp/ngcp-panel-tests-selenium-build-deps_1.0_all.deb
RUN apt-get --assume-yes -f install

RUN wget http://deb.sipwise.com/files/libselenium-remote-driver-perl_0.26-1~bpo80+1_all.deb
RUN dpkg --force-depends -i libselenium-remote-driver-perl_0.26-1~bpo80+1_all.deb
RUN apt-get --assume-yes -f install

# for prove execution by developers
RUN wget http://deb.sipwise.com/files/libtest-pretty-perl_0.31-1~bpo80+1_all.deb
RUN dpkg --force-depends -i libtest-pretty-perl_0.31-1~bpo80+1_all.deb
RUN apt-get --assume-yes -f install

RUN echo "cd /code && ./t/selenium/testrunner 1.2.3.4" >/home/selenium/.bash_history
RUN echo "su - selenium" >/root/.bash_history
EXPOSE 5999

COPY jenkins_docker_run /home/selenium/

WORKDIR /home/selenium

################################################################################
# Instructions for usage
# ----------------------
# When you want to build the base image from scratch (jump to the next section if you don't want to build yourself!):
# % docker build --tag="ngcp-panel-tests-selenium-jessie" .
# % docker run --rm -p 5999:5999 -i -t -v $(pwd)/../..:/code:rw ngcp-panel-tests-selenium-jessie:latest bash
#
# Use the existing docker image:
# % docker pull docker.mgm.sipwise.com/ngcp-panel-tests-selenium-jessie
# % docker run --rm -p 5999:5999 -i -t -v $(pwd)/../..:/code:rw docker.mgm.sipwise.com/ngcp-panel-tests-selenium-jessie:latest bash
#
# Inside docker:
#   su - selenium
#   cd /code && ./t/selenium/testrunner $IP_OF_NGCP_SYSTEM # IP_OF_NGCP_SYSTEM can be e.g. IP of a `vagrant up ce-trunk` system (eth1)
#
# On host (where vncviewer can be e.g. from Debian package xvnc4viewer):
# % vncviewer geometry=1280x1024x16 localhost:5999
################################################################################
