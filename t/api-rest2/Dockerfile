# DOCKER_NAME=ngcp-panel-tests-rest-api2-bookworm
FROM docker.mgm.sipwise.com/sipwise-bookworm:latest

# Important! Update this no-op ENV variable when this Dockerfile
# is updated with the current date. It will force refresh of all
# of the base images and things like `apt-get update` won't be using
# old cached versions when the Dockerfile is built.
ENV REFRESHED_AT 2023-06-26

# files that get-code generates
COPY t/api-rest/sources.list.d/builddeps.list /etc/apt/sources.list.d/
COPY t/api-rest/sources.list.d/preferences /etc/apt/preferences.d/

RUN apt-get update && \
    apt-get install --assume-yes \
      libcpanel-json-xs-perl \
      libdata-walk-perl \
      libdatetime-format-iso8601-perl \
      libdatetime-format-strptime-perl \
      liblog-log4perl-perl \
      libmoose-perl \
      liburi-perl \
      libwww-perl \
      libyaml-libyaml-perl \
      && echo "Done"

RUN echo "cd /code && ./t/api-rest2/testrunner 1.2.3.4" > /root/.bash_history

WORKDIR /code/

################################################################################
# Instructions for usage
# ----------------------
# When you want to build the base image from scratch
# jump to the next section if you don't want to build yourself!:
#
# you need to put the proper NGCP sources at t/api-rest2/sources.list.d/builddeps.list for instance, trunk:
# % echo "deb https://deb.sipwise.com/autobuild/ release-trunk-bookworm main" > t/api-rest2/sources.list.d/builddeps.list
#
# NOTE: run the following command (from root folder of git repository):
# % docker build --tag="ngcp-panel-tests-rest-api2-bookworm" -f t/api-rest2/Dockerfile .
# % docker run --rm -i -t -v $(pwd):/code:ro -v $(pwd):/results:rw ngcp-panel-tests-rest-api2-bookworm:latest bash
#
# Use the existing docker image (run from ngcp-panel base directory):
# % docker pull docker.mgm.sipwise.com/ngcp-panel-tests-rest-api2-bookworm
# % docker run --rm -i -t -v $(pwd):/code:ro -v $(pwd):/results:rw docker.mgm.sipwise.com/ngcp-panel-tests-rest-api2-bookworm:latest bash
#
# Inside docker. To run the full REST-API-2 test suite:
#   ./t/api-rest2/testrunner $IP_OF_NGCP_SYSTEM # IP_OF_NGCP_SYSTEM can be e.g. IP of a `vagrant up ce-trunk` system (eth1)
# To run only a particular test (e.g. the api-customers.t):
#   ./t/api-rest2/testrunner $IP_OF_NGCP_SYSTEM ./t/api-rest2/some_test.yaml
################################################################################
