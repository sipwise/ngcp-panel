# DOCKER_NAME=ngcp-panel-tests-selenium-bookworm
FROM docker.mgm.sipwise.com/sipwise-bookworm:latest

# Important! Update this no-op ENV variable when this Dockerfile
# is updated with the current date. It will force refresh of all
# of the base images and things like `apt-get update` won't be using
# old cached versions when the Dockerfile is built.
ENV REFRESHED_AT 2023-07-05

RUN apt-get update
RUN apt-get install --assume-yes \
        apt-utils \
        curl \
        devscripts \
        fluxbox \
        git \
        libdbus-glib-1-2 \
        libgtk-3-0 \
        lsof \
        net-tools \
        procps \
        python3 \
        python3-coverage \
        python3-nose2 \
        python3-selenium \
        tigervnc-standalone-server \
        unzip \
        vim-tiny \
        wget \
        xterm

RUN adduser --disabled-password --gecos=Selenium-User selenium

WORKDIR /home/selenium/

# installing geckodriver (0.33.0)
RUN wget http://deb.sipwise.com/files/geckodriver-v0.33.0-linux64.tar.gz && \
    tar xvf geckodriver-v0.33.0-linux64.tar.gz && \
    ln -s /home/selenium/geckodriver /usr/bin/geckodriver && \
    rm -f geckodriver-v0.33.0-linux64.tar.gz

# installing firefox (lang=en_US) (114.0.2)
RUN wget http://deb.sipwise.com/files/firefox-114.0.2.tar.bz2 && \
    tar xvf firefox-114.0.2.tar.bz2 && \
    ln -s /home/selenium/firefox/firefox /usr/bin/firefox && \
    rm -f firefox-114.0.2.tar.bz2

# installing chromedriver (114.0.5735.90)
RUN wget http://deb.sipwise.com/files/chromedriver_linux64_114.zip && \
    unzip chromedriver_linux64_114.zip && \
    #ln -s /home/selenium/chromedriver /usr/bin/chromedriver && \
    rm -f chromedriver_linux64114.zip

# installing chrome (114.0.5735.198)
RUN wget http://deb.sipwise.com/files/google-chrome-stable_114_amd64.deb && \
    apt install -y ./google-chrome-stable_114_amd64.deb && \
    rm -f google-chrome-stable_114_amd64.deb

RUN echo "cd /code && ./t/selenium/testrunner 1.2.3.4 /code/ tap" >/home/selenium/.bash_history
RUN echo "su - selenium" >/root/.bash_history
EXPOSE 5999

COPY t/selenium/jenkins_docker_run /home/selenium/
COPY t/selenium/webdriver_prefs.json /usr/lib/python3/dist-packages/selenium/webdriver/firefox/

################################################################################
# Instructions for usage
# ----------------------
# When you want to build the base image from scratch (jump to the next section if you don't want to build yourself!):
# NOTE: run the following command from root folder of git repository:
# % docker build --tag="ngcp-panel-tests-selenium-bookworm" -f t/selenium/Dockerfile .
# % docker run --rm -p 5999:5999 --shm-size 4g -i -t -v $(pwd):/code:rw ngcp-panel-tests-selenium-bookworm:latest bash
#
# Use the existing docker image:
# % docker pull docker.mgm.sipwise.com/ngcp-panel-tests-selenium-bookworm
# % docker run --rm -p 5999:5999 --shm-size 4g -i -t -v $(pwd):/code:rw docker.mgm.sipwise.com/ngcp-panel-tests-selenium-bookworm:latest bash
#
# Inside docker:
#   su - selenium
#   cd /code && ./t/selenium/testrunner $IP_OF_NGCP_SYSTEM # IP_OF_NGCP_SYSTEM can be e.g. IP of a `vagrant up ce-trunk` system (eth1)
#
# On host (where vncviewer can be e.g. from Debian package tigervnc-viewer):
# % vncviewer geometry=1280x1024x16 localhost:5999
################################################################################
