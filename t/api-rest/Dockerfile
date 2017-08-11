# DOCKER_NAME=ngcp-panel-tests-rest-api-jessie
FROM docker.mgm.sipwise.com/sipwise-jessie:latest

# Important! Update this no-op ENV variable when this Dockerfile
# is updated with the current date. It will force refresh of all
# of the base images and things like `apt-get update` won't be using
# old cached versions when the Dockerfile is built.
ENV REFRESHED_AT 2017-06-30

# files that get-code generates
COPY t/api-rest/sources.list.d/builddeps.list /etc/apt/sources.list.d/
COPY t/api-rest/sources.list.d/preferences /etc/apt/preferences.d/

RUN apt-get update
RUN apt-get install --assume-yes \
	devscripts \
        git \
        libtap-formatter-junit-perl \
        libdata-printer-perl \
        lsof \
        net-tools \
        vim-tiny \
        wget

RUN adduser --disabled-password --gecos="REST-API Testuser" testuser

WORKDIR /tmp/
COPY t/api-rest/control /tmp/
RUN mk-build-deps /tmp/control
RUN dpkg --force-depends -i /tmp/ngcp-panel-tests-rest-api-build-deps_1.0_all.deb
RUN apt-get --assume-yes -f install

# for prove execution
RUN wget http://deb.sipwise.com/files/libtest-pretty-perl_0.31-1~bpo80+1_all.deb
RUN dpkg --force-depends -i libtest-pretty-perl_0.31-1~bpo80+1_all.deb
RUN apt-get --assume-yes -f install

RUN apt-get clean

RUN echo "cd /code && ./t/api-rest/testrunner 1.2.3.4" > /home/testuser/.bash_history
RUN echo "su - testuser" > /root/.bash_history

WORKDIR /home/testuser

################################################################################
# Instructions for usage
# ----------------------
# When you want to build the base image from scratch
# jump to the next section if you don't want to build yourself!:
#
# you need to put the proper NGCP sources at t/sources.list.d/builddeps.list
# for instance, trunk:
# echo "deb https://deb.sipwise.com/autobuild/ release-trunk-jessie main" > /
#  t/sources.list.d/builddeps.list
#
# NOTE: run the following command from root folder of git repository:
# % docker build --tag="ngcp-panel-tests-rest-api-jessie" -f t/api-rest/Dockerfile .
# % docker run --rm -i -t -v $(pwd):/code:rw ngcp-panel-tests-rest-api-jessie:latest bash
#
# Use the existing docker image (run from ngcp-panel base directory):
# % docker pull docker.mgm.sipwise.com/ngcp-panel-tests-rest-api-jessie
# % docker run --rm -i -t -v $(pwd):/code:rw docker.mgm.sipwise.com/ngcp-panel-tests-rest-api-jessie:latest bash
#
# Inside docker:
#   su - testuser
#   cd /code
# To run the full test suite:
#   ./t/api-rest/testrunner $IP_OF_NGCP_SYSTEM # IP_OF_NGCP_SYSTEM can be e.g. IP of a `vagrant up ce-trunk` system (eth1)
# To run only a particular test (e.g. the api-customers.t):
#   ./t/api-rest/testrunner $IP_OF_NGCP_SYSTEM ./t/api-rest/api-customers.t
################################################################################
