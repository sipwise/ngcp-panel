# DOCKER_NAME=ngcp-panel-tests-selenium-buster
FROM docker.mgm.sipwise.com/sipwise-buster:latest

# Important! Update this no-op ENV variable when this Dockerfile
# is updated with the current date. It will force refresh of all
# of the base images and things like `apt-get update` won't be using
# old cached versions when the Dockerfile is built.
ENV REFRESHED_AT 2019-06-27

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
# this is a workaround until upstream released v1.21:
RUN wget https://deb.sipwise.com/files/libselenium-remote-driver-perl_1.20-0.1-git-16.orig.tar.xz
RUN tar xvf libselenium-remote-driver-perl_1.20-0.1-git-16.orig.tar.xz
RUN apt-get --assume-yes -f install libarchive-zip-perl libfile-which-perl libhttp-message-perl libio-string-perl libjson-perl libmoo-perl libnamespace-clean-perl libsub-install-perl libtest-longstring-perl libtest-time-perl libtry-tiny-perl libwww-perl libxml-simple-perl
RUN wget https://deb.sipwise.com/files/geckodriver-v0.18.0-linux64.tar.gz
RUN tar xvf geckodriver-v0.18.0-linux64.tar.gz
RUN ln -s /home/selenium/geckodriver /usr/bin/geckodriver

# firefox-esr 52.2.0esr-1~deb9u1 from Debian/buster fails with geckodriver e.g. in click events
RUN wget https://deb.sipwise.com/files/firefox-54.0.tar.bz2
RUN tar xvf firefox-54.0.tar.bz2
RUN ln -s /home/selenium/firefox/firefox /usr/bin/firefox
# runtime dependencies for firefox
RUN apt-get --assume-yes install libgtk-3-0 libdbus-glib-1-2

# for prove execution by developers
RUN wget https://deb.sipwise.com/files/libtest-pretty-perl_0.32-0.1~bpo9+1_all.deb
RUN dpkg --force-depends -i libtest-pretty-perl_0.32-0.1~bpo9+1_all.deb
RUN apt-get --assume-yes -f install

# this is a workaround with PERL5LIB= ... until we've a proper libselenium-remote-driver-perl package again
RUN echo "cd /code && PERL5LIB=/home/selenium/Selenium-Remote-Driver/lib/ ./t/selenium/testrunner 1.2.3.4" >/home/selenium/.bash_history
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
