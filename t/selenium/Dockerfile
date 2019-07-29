# DOCKER_NAME=ngcp-panel-tests-selenium-buster
FROM docker.mgm.sipwise.com/sipwise-buster:latest

# Important! Update this no-op ENV variable when this Dockerfile
# is updated with the current date. It will force refresh of all
# of the base images and things like `apt-get update` won't be using
# old cached versions when the Dockerfile is built.
ENV REFRESHED_AT 2019-07-29

RUN apt-get update
RUN apt-get install --assume-yes \
        curl \
        devscripts \
        fluxbox \
        git \
        libtap-formatter-junit-perl \
        lsof \
        net-tools \
        procps \
        vim-tiny \
        tigervnc-standalone-server \
        wget \
        xterm

# NOTE: we used to use selenium for testing, nowadays we're using
# only firefox with geckodriver and libselenium-remote-driver-perl
# without the need for selenium
RUN adduser --disabled-password --gecos=Selenium-User selenium

WORKDIR /home/selenium/

# build-dependencies
COPY t/selenium/control /home/selenium/control
RUN mk-build-deps /home/selenium/control
RUN dpkg --force-depends -i /home/selenium/ngcp-panel-tests-selenium-build-deps_1.0_all.deb
RUN apt-get --assume-yes -f install

# the connection between firefox and our selenium tests
RUN wget http://deb.sipwise.com/files/Selenium-Remote-Driver-1.33.tar.gz && \
    tar xvf Selenium-Remote-Driver-1.33.tar.gz && \
    mv Selenium-Remote-Driver-1.33 Selenium-Remote-Driver && \
    rm -f Selenium-Remote-Driver-1.33.tar.gz
RUN apt-get --assume-yes -f install libarchive-zip-perl libfile-which-perl libhttp-message-perl libio-string-perl libjson-perl libmoo-perl libnamespace-clean-perl libsub-install-perl libtest-longstring-perl libtest-time-perl libtry-tiny-perl libwww-perl libxml-simple-perl
RUN wget http://deb.sipwise.com/files/geckodriver-v0.24.0-linux64.tar.gz && \
    tar xvf geckodriver-v0.24.0-linux64.tar.gz && \
    ln -s /home/selenium/geckodriver /usr/bin/geckodriver && \
    rm -f geckodriver-v0.24.0-linux64.tar.gz

# pulling firefox 68.0.1 (download en_US version of firefox package)
RUN wget http://deb.sipwise.com/files/firefox-68.0.1.tar.bz2 && \
    tar xvf firefox-68.0.1.tar.bz2 && \
    ln -s /home/selenium/firefox/firefox /usr/bin/firefox && \
    rm -f firefox-68.0.1.tar.bz2

# runtime dependencies for firefox
RUN apt-get --assume-yes install libgtk-3-0 libdbus-glib-1-2

# this is a workaround with PERL5LIB= ... until we've a proper libselenium-remote-driver-perl package again
RUN echo "cd /code && PERL5LIB=/home/selenium/Selenium-Remote-Driver/lib/ ./t/selenium/testrunner 1.2.3.4 /code/ tap" >/home/selenium/.bash_history
RUN echo "su - selenium" >/root/.bash_history
EXPOSE 5999

COPY t/selenium/jenkins_docker_run /home/selenium/

################################################################################
# Instructions for usage
# ----------------------
# When you want to build the base image from scratch (jump to the next section if you don't want to build yourself!):
# NOTE: run the following command from root folder of git repository:
# % docker build --tag="ngcp-panel-tests-selenium-buster" -f t/selenium/Dockerfile .
# % docker run --rm -p 5999:5999 -i -t -v $(pwd):/code:rw ngcp-panel-tests-selenium-buster:latest bash
#
# Use the existing docker image:
# % docker pull docker.mgm.sipwise.com/ngcp-panel-tests-selenium-buster
# % docker run --rm -p 5999:5999 -i -t -v $(pwd):/code:rw docker.mgm.sipwise.com/ngcp-panel-tests-selenium-buster:latest bash
#
# Inside docker:
#   su - selenium
#   cd /code && ./t/selenium/testrunner $IP_OF_NGCP_SYSTEM # IP_OF_NGCP_SYSTEM can be e.g. IP of a `vagrant up ce-trunk` system (eth1)
#
# On host (where vncviewer can be e.g. from Debian package tigervnc-viewer):
# % vncviewer geometry=1280x1024x16 localhost:5999
################################################################################
